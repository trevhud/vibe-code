import { z } from 'zod';

// --- Shared types ---

export const Priority = z.enum(['interrupt', 'queue', 'silent']);
export type Priority = z.infer<typeof Priority>;

export const EventCategory = z.enum(['question', 'error', 'completion', 'permission', 'progress']);
export type EventCategory = z.infer<typeof EventCategory>;

export const SessionState = z.enum(['active', 'idle', 'disconnected']);
export type SessionState = z.infer<typeof SessionState>;

export const DiscoveredSession = z.object({
  id: z.string(),
  projectPath: z.string(),
  projectName: z.string(),
  tmuxSession: z.string().optional(),
  lastActivity: z.string().optional(),
  isActive: z.boolean(),
});
export type DiscoveredSession = z.infer<typeof DiscoveredSession>;

// --- Upstream messages (Phone → Relay) ---

const AuthMessage = z.object({
  type: z.literal('auth'),
  token: z.string(),
});

const InputMessage = z.object({
  type: z.literal('input'),
  sessionId: z.string(),
  text: z.string(),
});

const SessionListRequestMessage = z.object({
  type: z.literal('session_list_request'),
});

const AttachMessage = z.object({
  type: z.literal('attach'),
  sessionId: z.string(),
});

const DetachMessage = z.object({
  type: z.literal('detach'),
});

const PongMessage = z.object({
  type: z.literal('pong'),
});

export const UpstreamMessage = z.discriminatedUnion('type', [
  AuthMessage,
  InputMessage,
  SessionListRequestMessage,
  AttachMessage,
  DetachMessage,
  PongMessage,
]);
export type UpstreamMessage = z.infer<typeof UpstreamMessage>;

// --- Downstream messages (Relay → Phone) ---

const AuthResultMessage = z.object({
  type: z.literal('auth_result'),
  success: z.boolean(),
  error: z.string().optional(),
});

const SessionListMessage = z.object({
  type: z.literal('session_list'),
  sessions: z.array(DiscoveredSession),
});

const AgentEventMessage = z.object({
  type: z.literal('agent_event'),
  sessionId: z.string(),
  priority: Priority,
  category: EventCategory,
  summary: z.string(),
  timestamp: z.string(),
});

const InputAckMessage = z.object({
  type: z.literal('input_ack'),
  sessionId: z.string(),
  success: z.boolean(),
  error: z.string().optional(),
});

const SessionStateMessage = z.object({
  type: z.literal('session_state'),
  sessionId: z.string(),
  state: SessionState,
});

const SessionHistoryEvent = z.object({
  priority: Priority,
  category: EventCategory,
  summary: z.string(),
  timestamp: z.string(),
});

const SessionHistoryMessage = z.object({
  type: z.literal('session_history'),
  sessionId: z.string(),
  events: z.array(SessionHistoryEvent),
});

const ContextUpdateMessage = z.object({
  type: z.literal('context_update'),
  sessionId: z.string(),
  context: z.string(),
});

const PingMessage = z.object({
  type: z.literal('ping'),
});

export const DownstreamMessage = z.discriminatedUnion('type', [
  AuthResultMessage,
  SessionListMessage,
  AgentEventMessage,
  InputAckMessage,
  SessionStateMessage,
  SessionHistoryMessage,
  ContextUpdateMessage,
  PingMessage,
]);
export type DownstreamMessage = z.infer<typeof DownstreamMessage>;

// --- Helpers ---

export function encodeDownstream(msg: DownstreamMessage): string {
  return JSON.stringify(msg);
}

export function parseUpstream(raw: string): { success: true; data: UpstreamMessage } | { success: false; error: string } {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return { success: false, error: 'Invalid JSON' };
  }
  const result = UpstreamMessage.safeParse(parsed);
  if (!result.success) {
    return { success: false, error: result.error.issues.map(i => i.message).join(', ') };
  }
  return { success: true, data: result.data };
}
