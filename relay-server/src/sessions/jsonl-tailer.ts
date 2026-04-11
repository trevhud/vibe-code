import { watch, type FSWatcher } from 'chokidar';
import { openSync, readSync, fstatSync, closeSync, statSync } from 'node:fs';

export interface JsonlRecord {
  type: string;
  message?: {
    role?: string;
    content?: unknown;
    stop_reason?: string;
    [key: string]: unknown;
  };
  sessionId?: string;
  timestamp?: string;
  [key: string]: unknown;
}

export type JsonlEventCallback = (record: JsonlRecord) => void;

/**
 * Tails a JSONL file, emitting parsed records for new lines.
 * Uses chokidar to watch for file changes, then reads from the last offset.
 * Handles partial writes by buffering incomplete lines.
 */
export class JsonlTailer {
  private filePath: string;
  private callback: JsonlEventCallback;
  private watcher: FSWatcher | null = null;
  private offset: number = 0;
  private partialLine: string = '';
  private stopped: boolean = false;

  constructor(filePath: string, callback: JsonlEventCallback) {
    this.filePath = filePath;
    this.callback = callback;
  }

  /**
   * Start tailing from the current end of file (only new content).
   */
  start(): void {
    this.stopped = false;

    // Seek to end of file
    try {
      const fd = openSync(this.filePath, 'r');
      const stats = fstatSync(fd);
      this.offset = stats.size;
      closeSync(fd);
    } catch {
      this.offset = 0;
    }

    this.watcher = watch(this.filePath, {
      persistent: false,
      awaitWriteFinish: {
        stabilityThreshold: 100,
        pollInterval: 50,
      },
    });

    this.watcher.on('change', () => {
      if (!this.stopped) {
        this.readNewContent();
      }
    });
  }

  /**
   * Start tailing and also replay existing content from the beginning.
   */
  startWithReplay(): void {
    this.stopped = false;
    this.offset = 0;

    this.watcher = watch(this.filePath, {
      persistent: false,
      awaitWriteFinish: {
        stabilityThreshold: 100,
        pollInterval: 50,
      },
    });

    // Read existing content first
    this.readNewContent();

    this.watcher.on('change', () => {
      if (!this.stopped) {
        this.readNewContent();
      }
    });
  }

  stop(): void {
    this.stopped = true;
    this.watcher?.close();
    this.watcher = null;
    this.partialLine = '';
  }

  /**
   * Read recent records from the tail of a JSONL file without watching.
   */
  static readRecentRecords(filePath: string, maxBytes = 64_000): JsonlRecord[] {
    try {
      const stat = statSync(filePath);
      const fileSize = stat.size;
      const readFrom = Math.max(0, fileSize - maxBytes);
      const bytesToRead = fileSize - readFrom;

      const fd = openSync(filePath, 'r');
      const buffer = Buffer.alloc(bytesToRead);
      readSync(fd, buffer, 0, bytesToRead, readFrom);
      closeSync(fd);

      const text = buffer.toString('utf-8');
      const lines = text.split('\n');

      // If we started mid-file, drop the first (potentially partial) line
      if (readFrom > 0) {
        lines.shift();
      }

      const records: JsonlRecord[] = [];
      for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed) continue;
        try {
          records.push(JSON.parse(trimmed) as JsonlRecord);
        } catch {
          // skip malformed
        }
      }
      return records;
    } catch {
      return [];
    }
  }

  private readNewContent(): void {
    try {
      const fd = openSync(this.filePath, 'r');
      const stats = fstatSync(fd);
      const newSize = stats.size;

      if (newSize <= this.offset) {
        closeSync(fd);
        return;
      }

      const bytesToRead = newSize - this.offset;
      const buffer = Buffer.alloc(bytesToRead);
      readSync(fd, buffer, 0, bytesToRead, this.offset);
      closeSync(fd);

      this.offset = newSize;

      const text = this.partialLine + buffer.toString('utf-8');
      const lines = text.split('\n');

      // Last element is either '' (if text ended with \n) or a partial line
      this.partialLine = lines.pop() ?? '';

      for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed) continue;

        try {
          const record = JSON.parse(trimmed) as JsonlRecord;
          this.callback(record);
        } catch {
          // Skip malformed lines (could be partial JSON from concurrent write)
        }
      }
    } catch {
      // File might be temporarily unavailable during rotation
    }
  }
}
