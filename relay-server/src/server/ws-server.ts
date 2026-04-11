import type { WebSocket } from 'ws';
import type { FastifyRequest } from 'fastify';
import { verifyToken, type TokenPayload } from './auth.js';
import {
  parseUpstream,
  encodeDownstream,
  type DownstreamMessage,
  type UpstreamMessage,
} from '../protocol/messages.js';
import type { RelayConfig } from '../config.js';

export interface AuthenticatedClient {
  id: string;
  deviceId: string;
  socket: WebSocket;
  attachedSessionId: string | null;
  authenticatedAt: Date;
}

export type MessageHandler = (client: AuthenticatedClient, msg: UpstreamMessage) => void;
export type DisconnectHandler = (clientId: string) => void;

/**
 * Manages WebSocket client lifecycle: auth, keepalive, message routing.
 */
export class WsServer {
  private clients = new Map<string, AuthenticatedClient>();
  private messageHandler: MessageHandler | null = null;
  private disconnectHandler: DisconnectHandler | null = null;
  private config: RelayConfig;
  private clientIdCounter = 0;

  constructor(config: RelayConfig) {
    this.config = config;
  }

  onMessage(handler: MessageHandler): void {
    this.messageHandler = handler;
  }

  onDisconnect(handler: DisconnectHandler): void {
    this.disconnectHandler = handler;
  }

  /** Send a downstream message to a specific client */
  send(clientId: string, msg: DownstreamMessage): void {
    const client = this.clients.get(clientId);
    if (client && client.socket.readyState === client.socket.OPEN) {
      client.socket.send(encodeDownstream(msg));
    }
  }

  /** Broadcast to all authenticated clients attached to a session */
  broadcastToSession(sessionId: string, msg: DownstreamMessage): void {
    for (const client of this.clients.values()) {
      if (client.attachedSessionId === sessionId) {
        this.send(client.id, msg);
      }
    }
  }

  /** Broadcast to all authenticated clients */
  broadcastToAll(msg: DownstreamMessage): void {
    for (const client of this.clients.values()) {
      this.send(client.id, msg);
    }
  }

  getClient(clientId: string): AuthenticatedClient | undefined {
    return this.clients.get(clientId);
  }

  getClients(): AuthenticatedClient[] {
    return Array.from(this.clients.values());
  }

  handleConnection(socket: WebSocket, request: FastifyRequest): void {
    const tempId = `pending-${++this.clientIdCounter}`;
    let authenticated = false;
    let clientId: string | null = null;

    // Auth timeout — disconnect if not authenticated within window
    const authTimer = setTimeout(() => {
      if (!authenticated) {
        socket.send(encodeDownstream({
          type: 'auth_result',
          success: false,
          error: 'Authentication timeout',
        }));
        socket.close(4001, 'Authentication timeout');
      }
    }, this.config.wsAuthTimeoutMs);

    // Ping keepalive
    const pingInterval = setInterval(() => {
      if (authenticated && socket.readyState === socket.OPEN) {
        socket.send(encodeDownstream({ type: 'ping' }));
      }
    }, this.config.wsPingIntervalMs);

    socket.on('message', (raw: Buffer) => {
      const result = parseUpstream(raw.toString());
      if (!result.success) {
        socket.send(encodeDownstream({
          type: 'auth_result',
          success: false,
          error: result.error,
        }));
        return;
      }

      const msg = result.data;

      // First message must be auth
      if (!authenticated) {
        if (msg.type !== 'auth') {
          socket.send(encodeDownstream({
            type: 'auth_result',
            success: false,
            error: 'First message must be auth',
          }));
          socket.close(4002, 'Not authenticated');
          return;
        }

        const payload = verifyToken(this.config.jwtSecretPath, msg.token);
        if (!payload) {
          socket.send(encodeDownstream({
            type: 'auth_result',
            success: false,
            error: 'Invalid token',
          }));
          socket.close(4003, 'Invalid token');
          return;
        }

        // Auth succeeded
        authenticated = true;
        clearTimeout(authTimer);
        clientId = `client-${payload.deviceId.slice(0, 8)}`;

        const client: AuthenticatedClient = {
          id: clientId,
          deviceId: payload.deviceId,
          socket,
          attachedSessionId: null,
          authenticatedAt: new Date(),
        };
        this.clients.set(clientId, client);

        request.log.info({ clientId, deviceId: payload.deviceId }, 'Client authenticated');
        socket.send(encodeDownstream({ type: 'auth_result', success: true }));
        return;
      }

      // Authenticated message handling
      const client = clientId ? this.clients.get(clientId) : undefined;
      if (!client) return;

      // Track attach/detach
      if (msg.type === 'attach') {
        client.attachedSessionId = msg.sessionId;
      } else if (msg.type === 'detach') {
        client.attachedSessionId = null;
      }

      this.messageHandler?.(client, msg);
    });

    socket.on('close', () => {
      clearTimeout(authTimer);
      clearInterval(pingInterval);
      if (clientId) {
        this.clients.delete(clientId);
        this.disconnectHandler?.(clientId);
        request.log.info({ clientId }, 'Client disconnected');
      }
    });

    socket.on('error', (err) => {
      request.log.error({ err, clientId }, 'WebSocket error');
    });
  }
}
