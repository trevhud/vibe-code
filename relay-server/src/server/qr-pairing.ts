import type { FastifyInstance } from 'fastify';
import { generateToken } from './auth.js';
import { v4 as uuidv4 } from 'uuid';
import QRCode from 'qrcode';
import { hostname, networkInterfaces } from 'node:os';

interface PairPayload {
  relayUrl: string;
  token: string;
  hostname: string;
}

function getLocalIP(): string {
  const nets = networkInterfaces();
  for (const name of Object.keys(nets)) {
    for (const net of nets[name] ?? []) {
      // Skip internal/loopback and IPv6
      if (!net.internal && net.family === 'IPv4') {
        return net.address;
      }
    }
  }
  return hostname();
}

export function registerPairingRoutes(
  fastify: FastifyInstance,
  opts: { port: number; jwtSecretPath: string; externalUrl?: string },
): void {
  function buildPayload(): PairPayload {
    const deviceId = uuidv4();
    const token = generateToken(opts.jwtSecretPath, deviceId);

    let relayUrl: string;
    let host: string;

    if (opts.externalUrl) {
      // External URL set — use it as default (works on any network)
      const base = opts.externalUrl.replace(/\/$/, '');
      relayUrl = `wss://${base.replace(/^https?:\/\//, '')}/ws`;
      host = new URL(base.startsWith('http') ? base : `https://${base}`).hostname;
    } else {
      // Fallback to local IP (only works on same Wi-Fi)
      host = getLocalIP();
      relayUrl = `ws://${host}:${opts.port}/ws`;
    }

    return { relayUrl, token, hostname: host };
  }

  // JSON endpoint for programmatic access
  fastify.get('/pair/json', async () => {
    return buildPayload();
  });

  // HTML page with scannable QR code
  fastify.get('/pair', async (_request, reply) => {
    const payload = buildPayload();
    const qrData = JSON.stringify(payload);
    const qrSvg = await QRCode.toString(qrData, { type: 'svg', margin: 2 });

    const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Vibe Code — Pair Device</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif;
      background: #0a0a0a; color: #e5e5e5;
      display: flex; justify-content: center; align-items: center;
      min-height: 100vh; padding: 24px;
    }
    .card {
      background: #1a1a1a; border-radius: 20px; padding: 40px;
      max-width: 420px; width: 100%; text-align: center;
      border: 1px solid #2a2a2a;
    }
    h1 { font-size: 24px; font-weight: 700; margin-bottom: 8px; }
    .subtitle { color: #888; font-size: 14px; margin-bottom: 32px; }
    .qr-container {
      background: white; border-radius: 12px; padding: 20px;
      display: inline-block; margin-bottom: 24px;
    }
    .qr-container svg { display: block; width: 240px; height: 240px; }
    .info { font-size: 13px; color: #666; line-height: 1.6; }
    .info code {
      background: #2a2a2a; padding: 2px 6px; border-radius: 4px;
      font-family: 'SF Mono', Monaco, monospace; font-size: 12px; color: #aaa;
    }
    .refresh {
      display: inline-block; margin-top: 20px; padding: 10px 24px;
      background: #2563eb; color: white; border: none; border-radius: 10px;
      font-size: 14px; font-weight: 600; cursor: pointer; text-decoration: none;
    }
    .refresh:hover { background: #1d4ed8; }
  </style>
</head>
<body>
  <div class="card">
    <h1>Vibe Code</h1>
    <p class="subtitle">Scan with the iOS app to connect</p>
    <div class="qr-container">${qrSvg}</div>
    <p class="info">
      Relay: <code>${payload.relayUrl}</code>
    </p>
    <a class="refresh" href="/pair">New Code</a>
  </div>
</body>
</html>`;

    return reply.type('text/html').send(html);
  });
}
