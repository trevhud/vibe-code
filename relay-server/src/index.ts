import Fastify from 'fastify';
import websocket from '@fastify/websocket';
import type { WebSocket } from 'ws';
import { loadConfig } from './config.js';
import { WsServer } from './server/ws-server.js';
import { registerPairingRoutes } from './server/qr-pairing.js';
import { registerLlmBridge } from './server/llm-bridge.js';
import { registerToolEndpoints } from './server/tool-endpoints.js';
import { SessionDiscovery } from './sessions/session-discovery.js';
import { TmuxBridge } from './sessions/tmux-bridge.js';
import { JsonlTailer } from './sessions/jsonl-tailer.js';
import { join } from 'node:path';
import { classifyEvent } from './pipeline/event-classifier.js';
import { summarizeEvent } from './pipeline/template-summarizer.js';
import { ContextManager } from './pipeline/context-manager.js';
import type { Priority, EventCategory } from './pipeline/types.js';

const config = loadConfig();
const fastify = Fastify({ logger: true });
const wsServer = new WsServer(config);
const sessionDiscovery = new SessionDiscovery(config.claudeProjectsDir, config.sessionCacheTtlMs);
const tmuxBridge = new TmuxBridge();
const contextManager = new ContextManager();

// Active tailers per client
const activeTailers = new Map<string, JsonlTailer>();

// Broadcast context updates to iOS via WebSocket
contextManager.onChange((sessionId, context) => {
  wsServer.broadcastToSession(sessionId, {
    type: 'context_update',
    sessionId,
    context,
  });
});

await fastify.register(websocket, {
  options: {
    maxPayload: 1_048_576,
  },
});

// Health check
fastify.get('/health', async () => ({
  status: 'ok',
  version: '0.2.0',
  uptime: process.uptime(),
  clients: wsServer.getClients().length,
}));

// Clean up tailers on client disconnect
wsServer.onDisconnect((clientId) => {
  activeTailers.get(clientId)?.stop();
  activeTailers.delete(clientId);
});

// QR pairing routes
registerPairingRoutes(fastify, {
  port: config.port,
  jwtSecretPath: config.jwtSecretPath,
  externalUrl: config.externalUrl,
});

// Legacy LLM bridge (returns empty SSE response)
registerLlmBridge(fastify);

// Server tool endpoints for ElevenLabs
registerToolEndpoints(fastify, { sessionDiscovery, tmuxBridge, contextManager });

// Message handlers
wsServer.onMessage((client, msg) => {
  switch (msg.type) {
    case 'session_list_request': {
      const sessions = sessionDiscovery.discoverSessions();
      wsServer.send(client.id, { type: 'session_list', sessions });
      break;
    }
    case 'attach': {
      // Stop any existing tailer for this client
      activeTailers.get(client.id)?.stop();

      // Resolve session → JSONL path
      const allSessions = sessionDiscovery.discoverSessions();
      const target = allSessions.find(s => s.id === msg.sessionId);
      if (!target) {
        wsServer.send(client.id, {
          type: 'session_state',
          sessionId: msg.sessionId,
          state: 'disconnected',
        });
        break;
      }

      // Build JSONL path from the session's project path
      const encodedDir = SessionDiscovery.encodePath(target.projectPath);
      const jsonlPath = join(config.claudeProjectsDir, encodedDir, `${msg.sessionId}.jsonl`);

      const sessionId = msg.sessionId;

      // Send recent history before starting live tail
      const recentRecords = JsonlTailer.readRecentRecords(jsonlPath);
      const historyEvents: Array<{
        priority: Priority;
        category: EventCategory;
        summary: string;
        timestamp: string;
      }> = [];
      for (const record of recentRecords) {
        const classified = classifyEvent(record);
        if (!classified) continue;
        historyEvents.push({
          priority: classified.priority,
          category: classified.category,
          summary: summarizeEvent(classified),
          timestamp: (record.timestamp as string) ?? new Date().toISOString(),
        });

        // Seed context manager with history
        contextManager.handleEvent(sessionId, record);
      }
      // Send last 20 interesting events
      const trimmed = historyEvents.slice(-20);
      if (trimmed.length > 0) {
        wsServer.send(client.id, {
          type: 'session_history',
          sessionId,
          events: trimmed,
        });
      }

      const tailer = new JsonlTailer(jsonlPath, (record) => {
        // Feed context manager with every record
        contextManager.handleEvent(sessionId, record);

        const classified = classifyEvent(record);
        if (!classified) return;

        const summary = summarizeEvent(classified);
        wsServer.broadcastToSession(sessionId, {
          type: 'agent_event',
          sessionId,
          priority: classified.priority,
          category: classified.category,
          summary,
          timestamp: new Date().toISOString(),
        });
        fastify.log.info(
          { sessionId, priority: classified.priority, category: classified.category },
          summary,
        );
      });
      tailer.start();
      activeTailers.set(client.id, tailer);

      wsServer.send(client.id, {
        type: 'session_state',
        sessionId: msg.sessionId,
        state: 'active',
      });
      fastify.log.info({ clientId: client.id, sessionId: msg.sessionId }, 'Attached to session');
      break;
    }
    case 'detach': {
      activeTailers.get(client.id)?.stop();
      activeTailers.delete(client.id);
      break;
    }
    case 'input': {
      // Resolve session → tmux target, then inject text
      const sessions = sessionDiscovery.discoverSessions();
      const session = sessions.find(s => s.id === msg.sessionId);
      if (!session?.tmuxSession) {
        wsServer.send(client.id, {
          type: 'input_ack',
          sessionId: msg.sessionId,
          success: false,
          error: session ? 'No tmux session for this project' : 'Session not found',
        });
        break;
      }
      tmuxBridge.sendInput(session.tmuxSession, msg.text)
        .then(() => {
          wsServer.send(client.id, {
            type: 'input_ack',
            sessionId: msg.sessionId,
            success: true,
          });
        })
        .catch((err: Error) => {
          wsServer.send(client.id, {
            type: 'input_ack',
            sessionId: msg.sessionId,
            success: false,
            error: err.message,
          });
        });
      break;
    }
    case 'pong':
      break;
    case 'auth':
      // Already handled by WsServer — shouldn't reach here
      break;
  }
});

// WebSocket endpoint
fastify.get('/ws', { websocket: true }, (socket: WebSocket, request) => {
  request.log.info('Client connected');
  wsServer.handleConnection(socket, request);
});

// Graceful shutdown
const signals: NodeJS.Signals[] = ['SIGINT', 'SIGTERM'];
for (const signal of signals) {
  process.on(signal, async () => {
    fastify.log.info(`Received ${signal}, shutting down`);
    await fastify.close();
    process.exit(0);
  });
}

try {
  await fastify.listen({ port: config.port, host: config.host });
  fastify.log.info(`Relay server listening on ${config.host}:${config.port}`);
} catch (err) {
  fastify.log.error(err);
  process.exit(1);
}

// Export for testing
export { fastify, wsServer, config };
