import { exec } from 'node:child_process';
import { promisify } from 'node:util';

const execAsync = promisify(exec);

/**
 * Bridge to tmux for injecting text into Claude Code sessions
 * and capturing pane output.
 */
export class TmuxBridge {
  /**
   * Send text input to a tmux pane via send-keys.
   * The target should be in the format "session:window.pane" (e.g. "main:2.1").
   */
  async sendInput(target: string, text: string): Promise<void> {
    // tmux send-keys needs careful escaping:
    // - We use the -l flag for literal text (avoids interpreting special keys)
    // - Then send Enter separately
    const escaped = this.escapeForShell(text);
    await execAsync(`tmux send-keys -t ${this.escapeTarget(target)} -l ${escaped}`, {
      timeout: 5000,
    });
    // Send Enter to submit
    await execAsync(`tmux send-keys -t ${this.escapeTarget(target)} Enter`, {
      timeout: 5000,
    });
  }

  /**
   * Send raw keys (like Enter, Escape, C-c) without the -l literal flag.
   */
  async sendKeys(target: string, keys: string): Promise<void> {
    await execAsync(`tmux send-keys -t ${this.escapeTarget(target)} ${keys}`, {
      timeout: 5000,
    });
  }

  /**
   * Capture the current visible content of a tmux pane.
   */
  async capturePane(target: string): Promise<string> {
    const { stdout } = await execAsync(
      `tmux capture-pane -t ${this.escapeTarget(target)} -p`,
      { timeout: 5000 },
    );
    return stdout;
  }

  /**
   * Check if a tmux target exists and is accessible.
   */
  async targetExists(target: string): Promise<boolean> {
    try {
      await execAsync(`tmux has-session -t ${this.escapeTarget(target)}`, {
        timeout: 5000,
      });
      return true;
    } catch {
      return false;
    }
  }

  /** Shell-escape a string for use as a tmux send-keys argument */
  private escapeForShell(text: string): string {
    // Single-quote the text, escaping any embedded single quotes
    return "'" + text.replace(/'/g, "'\\''") + "'";
  }

  /** Escape tmux target to prevent shell injection */
  private escapeTarget(target: string): string {
    // Tmux targets are like "session:window.pane" — only allow safe chars
    if (!/^[\w.:-]+$/.test(target)) {
      throw new Error(`Invalid tmux target: ${target}`);
    }
    return target;
  }
}
