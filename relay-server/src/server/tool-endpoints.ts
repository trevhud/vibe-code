import type { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import type { SessionDiscovery } from '../sessions/session-discovery.js';
import type { TmuxBridge } from '../sessions/tmux-bridge.js';
import type { ContextManager } from '../pipeline/context-manager.js';

interface ToolEndpointDeps {
  sessionDiscovery: SessionDiscovery;
  tmuxBridge: TmuxBridge;
  contextManager: ContextManager;
}

interface SendToClaudeBody {
  text: string;
  sessionId: string;
}

interface GetClaudeStatusBody {
  sessionId: string;
}

/**
 * Register HTTP endpoints for ElevenLabs server tools.
 * These are called by ElevenLabs as webhook-based server tools
 * when the voice agent's LLM decides to use them.
 */
export function registerToolEndpoints(
  fastify: FastifyInstance,
  { sessionDiscovery, tmuxBridge, contextManager }: ToolEndpointDeps,
): void {
  // Verify the shared secret from ElevenLabs server tool config
  function verifyToolAuth(request: FastifyRequest): boolean {
    const secret = process.env.VIBE_TOOL_SECRET;
    if (!secret) return true; // No secret configured = allow all (dev mode)
    const header = request.headers['x-vibe-tool-secret'] as string | undefined;
    return header === secret;
  }

  /**
   * POST /api/tools/send-to-claude
   *
   * ElevenLabs server tool webhook. Sends user text to Claude Code
   * via the session's tmux pane.
   */
  fastify.post('/api/tools/send-to-claude', async (request: FastifyRequest, reply: FastifyReply) => {
    if (!verifyToolAuth(request)) {
      return reply.status(401).send({ error: 'Unauthorized' });
    }

    const body = request.body as SendToClaudeBody;
    if (!body.text || !body.sessionId) {
      return reply.status(400).send({ error: 'Missing text or sessionId' });
    }

    const sessions = sessionDiscovery.discoverSessions();
    const session = sessions.find(s => s.id === body.sessionId);

    if (!session?.tmuxSession) {
      const error = session
        ? 'No active tmux pane for this session'
        : 'Session not found';
      request.log.warn({ sessionId: body.sessionId }, `send-to-claude: ${error}`);
      return reply.status(404).send({ error });
    }

    try {
      await tmuxBridge.sendInput(session.tmuxSession, `[Voice] ${body.text}`);
      request.log.info(
        { sessionId: body.sessionId, textLength: body.text.length },
        'send-to-claude: injected input',
      );
      return reply.send({ success: true });
    } catch (err) {
      request.log.error({ err, sessionId: body.sessionId }, 'send-to-claude: failed');
      return reply.status(500).send({ error: (err as Error).message });
    }
  });

  /**
   * POST /api/tools/get-claude-status
   *
   * ElevenLabs server tool webhook. Returns the current context
   * of what Claude Code is doing in the session.
   */
  fastify.post('/api/tools/get-claude-status', async (request: FastifyRequest, reply: FastifyReply) => {
    if (!verifyToolAuth(request)) {
      return reply.status(401).send({ error: 'Unauthorized' });
    }

    const body = request.body as GetClaudeStatusBody;
    if (!body.sessionId) {
      return reply.status(400).send({ error: 'Missing sessionId' });
    }

    const ctx = contextManager.getContext(body.sessionId);
    const summary = contextManager.getFormattedContext(body.sessionId);

    request.log.info({ sessionId: body.sessionId, status: ctx.status }, 'get-claude-status');

    return reply.send({
      status: ctx.status,
      summary,
      latestResponse: ctx.latestResponse,
      latestQuestion: ctx.latestQuestion,
      currentTool: ctx.currentTool,
    });
  });
}
