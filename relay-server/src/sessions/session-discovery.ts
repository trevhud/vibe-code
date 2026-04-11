import { readdirSync, statSync, readFileSync } from 'node:fs';
import { join, basename } from 'node:path';
import { execSync } from 'node:child_process';
import type { DiscoveredSession } from '../protocol/messages.js';

const log = (msg: string, data?: Record<string, unknown>) =>
  console.log(`[SessionDiscovery] ${msg}`, data ? JSON.stringify(data) : '');

interface TmuxPane {
  sessionName: string;
  windowIndex: number;
  paneIndex: number;
  currentCommand: string;
  currentPath: string;
}

interface CachedResult {
  sessions: DiscoveredSession[];
  timestamp: number;
}

/**
 * Discovers active Claude Code sessions by scanning:
 * 1. ~/.claude/projects/ for JSONL conversation files
 * 2. tmux panes running Claude Code processes
 */
export class SessionDiscovery {
  private claudeProjectsDir: string;
  private cacheTtlMs: number;
  private cache: CachedResult | null = null;

  constructor(claudeProjectsDir: string, cacheTtlMs: number) {
    this.claudeProjectsDir = claudeProjectsDir;
    this.cacheTtlMs = cacheTtlMs;
  }

  discoverSessions(): DiscoveredSession[] {
    if (this.cache && Date.now() - this.cache.timestamp < this.cacheTtlMs) {
      return this.cache.sessions;
    }

    const projectDirs = this.scanProjectDirs();
    const tmuxPanes = this.getTmuxPanes();
    const sessions = this.correlate(projectDirs, tmuxPanes);

    this.cache = { sessions, timestamp: Date.now() };
    return sessions;
  }

  invalidateCache(): void {
    this.cache = null;
  }

  /** Decode Claude's encoded dir name back to a filesystem path.
   *  Claude encodes `/` → `-` and `.` → `-`, so `--` means `/.` (hidden dirs).
   *  We use the filesystem to disambiguate by trying longest-match at each level. */
  static decodeDirName(encoded: string): string {
    // Step 1: Handle hidden dirs — `--` represents `/.`
    const normalized = encoded.replace(/^-/, '').replaceAll('--', '/.');

    // Step 2: Split on definite `/` separators (from step 1)
    const segments = normalized.split('/').filter(Boolean);

    // Step 3: Resolve each segment against the filesystem
    let current = '';
    for (const segment of segments) {
      current = SessionDiscovery.resolveSegment(current, segment);
    }

    return current || '/' + encoded.replace(/^-/, '').replace(/-/g, '/');
  }

  /** Given a parent directory and a dash-delimited segment, find the real path
   *  by trying longest component names first (e.g. "vibe-code" before "vibe"). */
  private static resolveSegment(parentPath: string, segment: string): string {
    const parts = segment.split('-').filter(Boolean);
    let current = parentPath;
    let i = 0;

    while (i < parts.length) {
      let matched = false;

      // Try longest match first — more specific names win
      for (let len = parts.length - i; len >= 1; len--) {
        const candidate = parts.slice(i, i + len).join('-');
        const candidatePath = current + '/' + candidate;

        if (i + len >= parts.length) {
          // Last component — just needs to exist on disk
          try { statSync(candidatePath); return candidatePath; } catch { /* try shorter */ }
        } else {
          // Intermediate — must be a directory
          try {
            if (statSync(candidatePath).isDirectory()) {
              current = candidatePath;
              i += len;
              matched = true;
              break;
            }
          } catch { /* try shorter */ }
        }
      }

      if (!matched) {
        // Nothing matched on disk — use single part and move on
        current = current + '/' + parts[i];
        i++;
      }
    }

    return current;
  }

  /** Encode a filesystem path to Claude's dir name format (both / and . become -) */
  static encodePath(path: string): string {
    return path.replace(/[/.]/g, '-');
  }

  private scanProjectDirs(): Map<string, ProjectInfo> {
    const projects = new Map<string, ProjectInfo>();

    let entries: string[];
    try {
      entries = readdirSync(this.claudeProjectsDir);
    } catch {
      return projects;
    }

    for (const entry of entries) {
      const dirPath = join(this.claudeProjectsDir, entry);
      try {
        const stat = statSync(dirPath);
        if (!stat.isDirectory()) continue;
      } catch {
        continue;
      }

      const projectPath = SessionDiscovery.decodeDirName(entry);
      const projectName = basename(projectPath);
      log('Decoded project dir', { encoded: entry, decoded: projectPath, projectName });

      // Find JSONL files and get the most recent one
      const jsonlFiles = this.findJsonlFiles(dirPath);
      if (jsonlFiles.length === 0) continue;

      const mostRecent = jsonlFiles[0]; // sorted by mtime desc
      const lastActivity = mostRecent.mtime.toISOString();
      const sessionId = mostRecent.sessionId;

      projects.set(projectPath, {
        sessionId,
        projectPath,
        projectName,
        lastActivity,
        encodedDir: entry,
      });
    }

    return projects;
  }

  private findJsonlFiles(dirPath: string): Array<{ sessionId: string; mtime: Date }> {
    try {
      const entries = readdirSync(dirPath);
      const jsonlFiles = entries
        .filter(f => f.endsWith('.jsonl'))
        .map(f => {
          const filePath = join(dirPath, f);
          const stat = statSync(filePath);
          return {
            sessionId: f.replace('.jsonl', ''),
            mtime: stat.mtime,
          };
        })
        .sort((a, b) => b.mtime.getTime() - a.mtime.getTime());

      return jsonlFiles;
    } catch {
      return [];
    }
  }

  private getTmuxPanes(): TmuxPane[] {
    try {
      const output = execSync(
        'tmux list-panes -a -F "#{session_name}:#{window_index}.#{pane_index} #{pane_current_command} #{pane_current_path}"',
        { encoding: 'utf-8', timeout: 5000 },
      );

      return output
        .trim()
        .split('\n')
        .filter(Boolean)
        .map(line => {
          // Format: "session:window.pane command path"
          const match = line.match(/^(.+):(\d+)\.(\d+)\s+(\S+)\s+(.+)$/);
          if (!match) return null;

          return {
            sessionName: match[1],
            windowIndex: parseInt(match[2]),
            paneIndex: parseInt(match[3]),
            currentCommand: match[4],
            currentPath: match[5],
          };
        })
        .filter((p): p is TmuxPane => p !== null);
    } catch {
      return [];
    }
  }

  /** Match projects with tmux panes running Claude Code */
  private correlate(
    projects: Map<string, ProjectInfo>,
    panes: TmuxPane[],
  ): DiscoveredSession[] {
    // Claude Code processes show up as version numbers (e.g. "2.1.42") or "claude" or "node"
    const claudePanes = panes.filter(p =>
      /^\d+\.\d+\.\d+$/.test(p.currentCommand) ||
      p.currentCommand === 'claude' ||
      p.currentCommand === 'claude-code'
    );
    log('Tmux panes', { all: panes.length, claude: claudePanes.length });
    for (const p of claudePanes) {
      log('  Claude pane', { target: `${p.sessionName}:${p.windowIndex}.${p.paneIndex}`, cmd: p.currentCommand, path: p.currentPath });
    }

    const sessions: DiscoveredSession[] = [];

    for (const [projectPath, project] of projects) {
      // Find a tmux pane running Claude in this project's directory
      const matchingPane = claudePanes.find(p =>
        p.currentPath === projectPath ||
        p.currentPath.startsWith(projectPath + '/')
      );

      const tmuxTarget = matchingPane
        ? `${matchingPane.sessionName}:${matchingPane.windowIndex}.${matchingPane.paneIndex}`
        : undefined;
      log('Session match', { projectPath, tmuxTarget: tmuxTarget ?? 'NONE', isActive: !!matchingPane });

      // Consider active if there's a matching tmux pane, or if JSONL was modified recently (5min)
      const recentThreshold = Date.now() - 5 * 60 * 1000;
      const isActive = !!matchingPane ||
        (project.lastActivity ? new Date(project.lastActivity).getTime() > recentThreshold : false);

      sessions.push({
        id: project.sessionId,
        projectPath: project.projectPath,
        projectName: project.projectName,
        tmuxSession: tmuxTarget,
        lastActivity: project.lastActivity,
        isActive,
      });
    }

    // Sort: active first, then by last activity
    sessions.sort((a, b) => {
      if (a.isActive !== b.isActive) return a.isActive ? -1 : 1;
      const aTime = a.lastActivity ? new Date(a.lastActivity).getTime() : 0;
      const bTime = b.lastActivity ? new Date(b.lastActivity).getTime() : 0;
      return bTime - aTime;
    });

    return sessions;
  }
}

interface ProjectInfo {
  sessionId: string;
  projectPath: string;
  projectName: string;
  lastActivity: string;
  encodedDir: string;
}
