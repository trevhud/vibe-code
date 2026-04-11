import { homedir } from 'node:os';
import { join } from 'node:path';

export interface RelayConfig {
  port: number;
  host: string;
  jwtSecretPath: string;
  claudeProjectsDir: string;
  vibeCodeDir: string;
  sessionCacheTtlMs: number;
  wsPingIntervalMs: number;
  wsAuthTimeoutMs: number;
  /** External base URL for pairing. Defaults to Tailscale Funnel. Override with VIBE_EXTERNAL_URL. */
  externalUrl: string;
}

function env(key: string, fallback: string): string {
  return process.env[key] ?? fallback;
}

function envInt(key: string, fallback: number): number {
  const val = process.env[key];
  return val ? parseInt(val, 10) : fallback;
}

const home = homedir();

export function loadConfig(): RelayConfig {
  return {
    port: envInt('VIBE_PORT', 3578),
    host: env('VIBE_HOST', '0.0.0.0'),
    jwtSecretPath: env('VIBE_JWT_SECRET_PATH', join(home, '.vibe-code', 'relay-secret.key')),
    claudeProjectsDir: env('VIBE_CLAUDE_PROJECTS_DIR', join(home, '.claude', 'projects')),
    vibeCodeDir: env('VIBE_CODE_DIR', join(home, '.vibe-code')),
    sessionCacheTtlMs: envInt('VIBE_SESSION_CACHE_TTL_MS', 5000),
    wsPingIntervalMs: envInt('VIBE_WS_PING_INTERVAL_MS', 30000),
    wsAuthTimeoutMs: envInt('VIBE_WS_AUTH_TIMEOUT_MS', 10000),
    externalUrl: env('VIBE_EXTERNAL_URL', ''),
  };
}
