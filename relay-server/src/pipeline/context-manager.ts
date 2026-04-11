import type { JsonlRecord } from '../sessions/jsonl-tailer.js';
import { classifyEvent } from './event-classifier.js';
import { summarizeEvent } from './template-summarizer.js';
import { extractSpeakableText } from './response-extractor.js';

export interface SessionContext {
  status: 'idle' | 'working' | 'waiting_for_input';
  recentEvents: Array<{ timestamp: string; summary: string }>;
  latestResponse: string | null;
  latestQuestion: string | null;
  currentTool: string | null;
}

const MAX_RECENT_EVENTS = 10;
const MAX_RESPONSE_LENGTH = 500;

/**
 * Maintains a rolling window of Claude Code activity per session.
 * Fed by the JSONL tailer callback — produces context for the
 * ElevenLabs `get_claude_status` server tool and contextual updates.
 */
export class ContextManager {
  private contexts = new Map<string, SessionContext>();
  private changeCallbacks: Array<(sessionId: string, context: string) => void> = [];
  private debounceTimers = new Map<string, ReturnType<typeof setTimeout>>();
  private static readonly DEBOUNCE_MS = 500;

  /** Register a callback fired when context changes significantly */
  onChange(cb: (sessionId: string, context: string) => void): void {
    this.changeCallbacks.push(cb);
  }

  /** Process a JSONL record and update session context */
  handleEvent(sessionId: string, record: JsonlRecord): void {
    const ctx = this.getOrCreate(sessionId);
    const prevStatus = ctx.status;
    const prevQuestion = ctx.latestQuestion;
    const prevResponse = ctx.latestResponse;

    // Classify and summarize for the event log
    const classified = classifyEvent(record);
    if (classified) {
      const summary = summarizeEvent(classified);
      ctx.recentEvents.push({
        timestamp: new Date().toISOString(),
        summary,
      });
      if (ctx.recentEvents.length > MAX_RECENT_EVENTS) {
        ctx.recentEvents.shift();
      }

      // Update status based on category
      switch (classified.category) {
        case 'question':
          ctx.status = 'waiting_for_input';
          break;
        case 'completion':
          ctx.status = 'idle';
          break;
        case 'error':
          ctx.status = 'idle';
          break;
        case 'progress':
          ctx.status = 'working';
          break;
      }

      // Track current tool
      if (classified.category === 'progress' && typeof classified.rawData === 'object' && classified.rawData !== null) {
        const block = classified.rawData as { type?: string; name?: string };
        if (block.type === 'tool_use' && block.name) {
          ctx.currentTool = block.name;
        }
      }
      if (classified.category === 'completion' || classified.category === 'question') {
        ctx.currentTool = null;
      }
    }

    // Extract speakable text for latest response/question tracking
    const speakable = extractSpeakableText(record);
    if (speakable) {
      if (speakable.isFinal) {
        // Check if this is a question (AskUserQuestion)
        const content = record.message?.content;
        const isQuestion = Array.isArray(content) && content.some(
          (b: unknown) =>
            typeof b === 'object' && b !== null &&
            'type' in b && (b as { type: string }).type === 'tool_use' &&
            'name' in b && (b as { name: string }).name === 'AskUserQuestion'
        );

        if (isQuestion) {
          ctx.latestQuestion = truncate(speakable.text, MAX_RESPONSE_LENGTH);
        } else {
          ctx.latestResponse = truncate(speakable.text, MAX_RESPONSE_LENGTH);
          ctx.latestQuestion = null;
        }
      }
    }

    // Fire change callback if something significant changed (debounced)
    const significantChange =
      ctx.status !== prevStatus ||
      ctx.latestQuestion !== prevQuestion ||
      (ctx.latestResponse !== prevResponse && ctx.status === 'idle');

    if (significantChange) {
      // Debounce to coalesce rapid status transitions (e.g. working → idle → waiting)
      // into a single context update, preventing the voice agent from being interrupted
      // by a burst of sendMessage() calls.
      const existing = this.debounceTimers.get(sessionId);
      if (existing) clearTimeout(existing);

      this.debounceTimers.set(sessionId, setTimeout(() => {
        this.debounceTimers.delete(sessionId);
        const formatted = this.getFormattedContext(sessionId);
        for (const cb of this.changeCallbacks) {
          cb(sessionId, formatted);
        }
      }, ContextManager.DEBOUNCE_MS));
    }
  }

  /** Get raw context for a session */
  getContext(sessionId: string): SessionContext {
    return this.getOrCreate(sessionId);
  }

  /** Get a concise text summary suitable for contextual_update */
  getFormattedContext(sessionId: string): string {
    const ctx = this.getOrCreate(sessionId);
    const parts: string[] = [];

    parts.push(`Status: ${ctx.status}`);

    if (ctx.currentTool) {
      parts.push(`Current tool: ${ctx.currentTool}`);
    }

    if (ctx.latestQuestion) {
      parts.push(`Claude is asking: ${ctx.latestQuestion}`);
    } else if (ctx.latestResponse && ctx.status === 'idle') {
      parts.push(`Latest response: ${ctx.latestResponse}`);
    }

    if (ctx.recentEvents.length > 0) {
      const last3 = ctx.recentEvents.slice(-3);
      parts.push('Recent activity: ' + last3.map(e => e.summary).join(' → '));
    }

    return parts.join('\n');
  }

  /** Clear context for a session */
  clearSession(sessionId: string): void {
    this.contexts.delete(sessionId);
    const timer = this.debounceTimers.get(sessionId);
    if (timer) {
      clearTimeout(timer);
      this.debounceTimers.delete(sessionId);
    }
  }

  private getOrCreate(sessionId: string): SessionContext {
    let ctx = this.contexts.get(sessionId);
    if (!ctx) {
      ctx = {
        status: 'idle',
        recentEvents: [],
        latestResponse: null,
        latestQuestion: null,
        currentTool: null,
      };
      this.contexts.set(sessionId, ctx);
    }
    return ctx;
  }
}

function truncate(text: string, max: number): string {
  if (text.length <= max) return text;
  return text.slice(0, max - 3) + '...';
}
