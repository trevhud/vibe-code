import type { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';

/**
 * Stub OpenAI-compatible chat completions endpoint.
 *
 * The custom LLM approach is replaced by ElevenLabs' built-in LLM
 * with server tools (send_to_claude, get_claude_status). This endpoint
 * is kept so that any lingering ElevenLabs agent config pointing here
 * won't error out — it just returns an empty SSE response.
 */

function makeChunk(content: string, finishReason: string | null = null): string {
  const chunk = {
    id: `chatcmpl-${Date.now()}`,
    object: 'chat.completion.chunk',
    created: Math.floor(Date.now() / 1000),
    model: 'vibe-code-relay',
    choices: [{
      delta: finishReason ? {} : { content },
      index: 0,
      finish_reason: finishReason,
    }],
  };
  return `data: ${JSON.stringify(chunk)}\n\n`;
}

export function registerLlmBridge(fastify: FastifyInstance): void {
  fastify.post('/v1/chat/completions', async (request: FastifyRequest, reply: FastifyReply) => {
    request.log.info('LLM bridge: legacy endpoint called, returning empty response');

    reply.raw.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
    });
    reply.raw.write(makeChunk('Voice commands are handled via server tools now.'));
    reply.raw.write(makeChunk('', 'stop'));
    reply.raw.write('data: [DONE]\n\n');
    reply.raw.end();
    return reply;
  });
}
