import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { dirname } from 'node:path';
import { randomBytes } from 'node:crypto';
import jwt from 'jsonwebtoken';

export interface TokenPayload {
  deviceId: string;
  iat: number; // auto-added by jwt.sign
}

type TokenInput = Omit<TokenPayload, 'iat'>;

let cachedSecret: string | null = null;

function ensureSecret(secretPath: string): string {
  if (cachedSecret) return cachedSecret;

  if (existsSync(secretPath)) {
    cachedSecret = readFileSync(secretPath, 'utf-8').trim();
    return cachedSecret;
  }

  // Auto-generate on first run
  const dir = dirname(secretPath);
  if (!existsSync(dir)) {
    mkdirSync(dir, { recursive: true });
  }

  const secret = randomBytes(64).toString('base64url');
  writeFileSync(secretPath, secret, { mode: 0o600 });
  cachedSecret = secret;
  return secret;
}

export function generateToken(secretPath: string, deviceId: string): string {
  const secret = ensureSecret(secretPath);
  return jwt.sign({ deviceId } satisfies TokenInput, secret, {
    algorithm: 'HS256',
    // No expiry — tokens are revoked by regenerating the secret
  });
}

export function verifyToken(secretPath: string, token: string): TokenPayload | null {
  const secret = ensureSecret(secretPath);
  try {
    return jwt.verify(token, secret, { algorithms: ['HS256'] }) as TokenPayload;
  } catch {
    return null;
  }
}

/** Invalidate all existing tokens by regenerating the secret */
export function rotateSecret(secretPath: string): void {
  cachedSecret = null;
  const dir = dirname(secretPath);
  if (!existsSync(dir)) {
    mkdirSync(dir, { recursive: true });
  }
  const secret = randomBytes(64).toString('base64url');
  writeFileSync(secretPath, secret, { mode: 0o600 });
  cachedSecret = secret;
}
