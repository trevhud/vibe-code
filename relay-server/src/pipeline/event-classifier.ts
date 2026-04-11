import type { JsonlRecord } from '../sessions/jsonl-tailer.js';
import type { ClassifiedEvent, Priority, EventCategory } from './types.js';

/**
 * Rule-based classifier that determines priority and category for JSONL events.
 *
 * Phase 1 focuses on INTERRUPT events (questions, errors, completions).
 * Everything else is SILENT.
 */
export function classifyEvent(record: JsonlRecord): ClassifiedEvent | null {
  const content = record.message?.content;

  // --- Assistant messages ---
  if (record.type === 'assistant' && Array.isArray(content)) {
    // Check for AskUserQuestion tool_use
    for (const block of content) {
      if (
        typeof block === 'object' &&
        block !== null &&
        'type' in block &&
        block.type === 'tool_use' &&
        'name' in block &&
        block.name === 'AskUserQuestion'
      ) {
        return { priority: 'interrupt', category: 'question', rawData: block };
      }
    }

    // Check for end_turn with text (completion)
    if (record.message?.stop_reason === 'end_turn') {
      const hasTextOnly = content.every(
        (b: unknown) =>
          typeof b === 'object' && b !== null && 'type' in b && (b as { type: string }).type === 'text'
      );
      if (hasTextOnly && content.length > 0) {
        return { priority: 'interrupt', category: 'completion', rawData: content };
      }
    }
  }

  // --- User messages with tool results (contains error info) ---
  if (record.type === 'user' && Array.isArray(content)) {
    for (const block of content) {
      if (
        typeof block === 'object' &&
        block !== null &&
        'type' in block &&
        block.type === 'tool_result'
      ) {
        const toolResult = block as {
          type: string;
          is_error?: boolean;
          content?: unknown;
          tool_use_id?: string;
        };

        if (toolResult.is_error) {
          return { priority: 'interrupt', category: 'error', rawData: toolResult };
        }

        // Check for stderr in Bash tool results (non-error but contains error output)
        const resultContent = toolResult.content;
        if (typeof resultContent === 'string' && hasErrorPattern(resultContent)) {
          return { priority: 'interrupt', category: 'error', rawData: toolResult };
        }
        if (Array.isArray(resultContent)) {
          for (const c of resultContent) {
            if (
              typeof c === 'object' &&
              c !== null &&
              'type' in c &&
              (c as { type: string }).type === 'text'
            ) {
              const text = (c as { text?: string }).text ?? '';
              if (hasErrorPattern(text)) {
                return { priority: 'interrupt', category: 'error', rawData: toolResult };
              }
            }
          }
        }
      }
    }
  }

  // --- Assistant messages with tool_use (progress events) ---
  if (record.type === 'assistant' && Array.isArray(content)) {
    for (const block of content) {
      if (
        typeof block === 'object' &&
        block !== null &&
        'type' in block &&
        block.type === 'tool_use'
      ) {
        return { priority: 'queue', category: 'progress', rawData: block };
      }
    }

    // Text blocks that aren't end_turn (intermediate assistant text)
    const textBlocks = content.filter(
      (b: unknown) => typeof b === 'object' && b !== null && 'type' in b && (b as { type: string }).type === 'text'
    );
    if (textBlocks.length > 0) {
      return { priority: 'queue', category: 'progress', rawData: textBlocks };
    }
  }

  // Everything else is silent
  return null;
}

/** Check if text contains patterns that indicate an error */
function hasErrorPattern(text: string): boolean {
  const firstLine = text.split('\n')[0] ?? '';
  const lower = firstLine.toLowerCase();

  return (
    lower.startsWith('exit code') && !lower.includes('exit code 0') ||
    lower.includes('error:') ||
    lower.includes('fatal:') ||
    lower.includes('panic:') ||
    lower.includes('traceback') ||
    lower.includes('exception:')
  );
}
