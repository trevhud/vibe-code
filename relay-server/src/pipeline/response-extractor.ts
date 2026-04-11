import type { JsonlRecord } from '../sessions/jsonl-tailer.js';

export interface SpeakableText {
  text: string;
  isFinal: boolean;
}

/**
 * Extract text suitable for ElevenLabs TTS from a JSONL record.
 * Only returns Claude's actual words — no canned/generated summaries.
 * Returns null if the record has nothing worth speaking.
 */
export function extractSpeakableText(record: JsonlRecord): SpeakableText | null {
  const content = record.message?.content;

  // --- Assistant messages ---
  if (record.type === 'assistant' && Array.isArray(content)) {
    // AskUserQuestion → speak the actual question text, close stream
    for (const block of content) {
      if (isToolUse(block) && getToolName(block) === 'AskUserQuestion') {
        const input = (block as { input?: { questions?: Array<{ question?: string }> } }).input;
        const questions = input?.questions;
        if (Array.isArray(questions) && questions.length > 0 && questions[0]?.question) {
          return { text: questions[0].question, isFinal: true };
        }
        return null;
      }
    }

    // end_turn + text blocks → final response
    if (record.message?.stop_reason === 'end_turn') {
      const textBlocks = content.filter(isTextBlock);
      if (textBlocks.length > 0) {
        const text = textBlocks.map((b) => (b as { text: string }).text).join('\n');
        return { text, isFinal: true };
      }
    }

    // Intermediate text (no end_turn, no tool_use only) → Claude thinking out loud
    const textBlocks = content.filter(isTextBlock);
    if (textBlocks.length > 0) {
      const text = textBlocks.map((b) => (b as { text: string }).text).join('\n');
      return { text, isFinal: false };
    }

    // Tool use with no text → skip (no canned summaries)
  }

  // --- User messages with error tool results ---
  if (record.type === 'user' && Array.isArray(content)) {
    for (const block of content) {
      if (isToolResult(block) && (block as { is_error?: boolean }).is_error) {
        const errorText = extractToolResultText(block);
        const firstLine = errorText.split('\n')[0]?.trim();
        if (firstLine) {
          return { text: firstLine, isFinal: true };
        }
      }
    }
  }

  return null;
}

// --- Helpers ---

function isTextBlock(block: unknown): boolean {
  return (
    typeof block === 'object' &&
    block !== null &&
    'type' in block &&
    (block as { type: string }).type === 'text'
  );
}

function isToolUse(block: unknown): boolean {
  return (
    typeof block === 'object' &&
    block !== null &&
    'type' in block &&
    (block as { type: string }).type === 'tool_use'
  );
}

function isToolResult(block: unknown): boolean {
  return (
    typeof block === 'object' &&
    block !== null &&
    'type' in block &&
    (block as { type: string }).type === 'tool_result'
  );
}

function getToolName(block: unknown): string | undefined {
  return (block as { name?: string }).name;
}

function extractToolResultText(block: unknown): string {
  const result = block as { content?: unknown };
  if (typeof result.content === 'string') return result.content;
  if (Array.isArray(result.content)) {
    for (const c of result.content) {
      if (isTextBlock(c)) {
        return (c as { text?: string }).text ?? '';
      }
    }
  }
  return '';
}
