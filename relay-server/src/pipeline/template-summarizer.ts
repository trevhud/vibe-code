import type { ClassifiedEvent } from './types.js';

const MAX_SUMMARY_LENGTH = 200;

/**
 * Generate a human-readable summary suitable for TTS from a classified event.
 */
export function summarizeEvent(event: ClassifiedEvent): string {
  switch (event.category) {
    case 'question':
      return summarizeQuestion(event.rawData);
    case 'error':
      return summarizeError(event.rawData);
    case 'completion':
      return summarizeCompletion(event.rawData);
    case 'permission':
      return 'Claude needs permission to proceed.';
    case 'progress':
      return summarizeProgress(event.rawData);
  }
}

function summarizeQuestion(raw: unknown): string {
  // AskUserQuestion tool_use block has input.questions[]
  if (typeof raw !== 'object' || raw === null) return 'Claude has a question.';

  const block = raw as { input?: { questions?: Array<{ question?: string }> } };
  const questions = block.input?.questions;

  if (Array.isArray(questions) && questions.length > 0) {
    const firstQuestion = questions[0]?.question;
    if (firstQuestion) {
      return truncate(firstQuestion, MAX_SUMMARY_LENGTH);
    }
  }

  return 'Claude has a question.';
}

function summarizeError(raw: unknown): string {
  if (typeof raw !== 'object' || raw === null) return 'An error occurred.';

  const toolResult = raw as { content?: unknown };
  const content = toolResult.content;

  let errorText = '';

  if (typeof content === 'string') {
    errorText = content;
  } else if (Array.isArray(content)) {
    for (const c of content) {
      if (typeof c === 'object' && c !== null && 'type' in c && (c as { type: string }).type === 'text') {
        errorText = (c as { text?: string }).text ?? '';
        break;
      }
    }
  }

  if (!errorText) return 'An error occurred.';

  // Extract the most informative line
  const lines = errorText.split('\n').filter(l => l.trim());
  const firstMeaningful = lines.find(l =>
    l.toLowerCase().includes('error') ||
    l.toLowerCase().includes('fatal') ||
    l.toLowerCase().includes('traceback') ||
    l.toLowerCase().includes('exit code')
  ) ?? lines[0] ?? '';

  return truncate(`Error: ${firstMeaningful.trim()}`, MAX_SUMMARY_LENGTH);
}

function summarizeCompletion(raw: unknown): string {
  // Extract last text block for context
  if (Array.isArray(raw)) {
    const lastText = [...raw].reverse().find(
      (b: unknown) => typeof b === 'object' && b !== null && 'type' in b && (b as { type: string }).type === 'text'
    );
    if (lastText && typeof lastText === 'object' && 'text' in lastText) {
      const text = (lastText as { text: string }).text;
      // If it's a short final message, use it
      if (text.length < MAX_SUMMARY_LENGTH) {
        return `Claude finished: ${text.trim()}`;
      }
    }
  }
  return 'Claude finished responding.';
}

function summarizeProgress(raw: unknown): string {
  // Tool use block
  if (typeof raw === 'object' && raw !== null && 'type' in raw) {
    const block = raw as { type: string; name?: string; input?: Record<string, unknown> };
    if (block.type === 'tool_use' && block.name) {
      const input = block.input;
      switch (block.name) {
        case 'Edit':
        case 'Write':
        case 'Read': {
          const filePath = input?.file_path as string | undefined;
          const fileName = filePath?.split('/').pop() ?? 'a file';
          const verb = block.name === 'Read' ? 'Reading' : 'Editing';
          return `${verb} ${fileName}`;
        }
        case 'Bash': {
          const command = input?.command as string | undefined;
          if (command) {
            const snippet = command.length > 60 ? command.slice(0, 60) + '...' : command;
            return `Running: ${snippet}`;
          }
          return 'Running a command';
        }
        case 'Grep':
        case 'Glob': {
          const pattern = input?.pattern as string | undefined;
          return pattern ? `Searching for ${pattern}` : 'Searching';
        }
        case 'Task': {
          const desc = input?.description as string | undefined;
          return desc ? `Agent: ${desc}` : 'Spawning agent';
        }
        default:
          return `Using ${block.name}`;
      }
    }
  }

  // Text blocks (intermediate assistant text)
  if (Array.isArray(raw)) {
    const first = raw[0];
    if (first && typeof first === 'object' && 'text' in first) {
      const text = (first as { text: string }).text;
      return truncate(text.trim(), MAX_SUMMARY_LENGTH);
    }
  }

  return 'Working...';
}

function truncate(text: string, maxLength: number): string {
  if (text.length <= maxLength) return text;
  return text.slice(0, maxLength - 3) + '...';
}
