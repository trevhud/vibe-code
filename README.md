# Vibe Code

A voice-first mobile companion for Claude Code. Talk to your coding sessions hands-free from your iPhone.

## How It Works

Vibe Code connects three components to create a voice loop between you and Claude Code:

1. **Relay Server** -- A Node.js process running on your Mac that discovers active Claude Code sessions by scanning `~/.claude/projects/` for JSONL session files and correlating them with tmux panes. It watches those files for new events and injects your voice commands into the correct tmux session.

2. **iOS App** -- A SwiftUI iPhone app with on-device speech recognition (SFSpeechRecognizer) and text-to-speech (AVSpeechSynthesizer). It connects to the relay server over WebSocket and provides the hands-free interface.

3. **Claude Code** -- Your existing Claude Code sessions, unchanged. The relay reads their JSONL output and writes input through tmux. No plugins or modifications required.

The result: you can walk away from your desk, speak a command, and hear errors, questions, and task completions read back to you.

## Features

- On-device speech-to-text with no cloud transcription dependency
- Text-to-speech with priority-based interrupts (errors and questions speak immediately)
- Automatic discovery of all active Claude Code sessions
- QR code pairing for quick phone-to-Mac setup
- JWT authentication with auto-generated secrets
- Exponential backoff reconnection on the iOS client
- Session history replay on attach (last 20 classified events)
- Event classification pipeline that filters noise -- only errors, questions, and completions are spoken
- Zero external Swift dependencies in the iOS app

## Architecture

```
Phone                         Mac
-----                         ---

Speak                         Claude Code writes to JSONL
  |                                      |
  v                                      v
STT (on-device)               JsonlTailer (chokidar watch)
  |                                      |
  v                                      v
RelayClient ---- WebSocket --- WsServer  EventClassifier
  (phone)                      |         |
                               |         v
                               |    TemplateSummarizer
                               |         |
                               |    agent_event (interrupt/queue/silent)
                               |         |
                               +-----> WebSocket --> phone --> TTS speaks it
                               |
                      input -->|
                               v
                          TmuxBridge
                               |
                               v
                     tmux send-keys --> Claude Code
```

**Voice command flow:** iPhone STT transcribes speech, sends it over WebSocket to the relay server, which injects it into the Claude Code tmux pane via `tmux send-keys`.

**Event notification flow:** Claude Code writes JSONL output. The relay tails the file, classifies each record (question, error, completion, or noise), summarizes it into TTS-friendly text, and pushes it to the phone. The iOS app speaks interrupt-priority events immediately.

## Tech Stack

### Relay Server

- Node.js 22+, ESM modules
- Fastify 5 with @fastify/websocket
- TypeScript 5 (strict mode)
- Zod for WebSocket message validation
- chokidar for file watching
- jsonwebtoken for JWT auth
- vitest for tests, tsx for dev hot-reload

### iOS App

- SwiftUI, iOS 17+
- URLSessionWebSocketTask (built-in WebSocket)
- SFSpeechRecognizer (on-device STT)
- AVSpeechSynthesizer (TTS)
- AVAudioSession for audio routing
- Keychain for credential storage
- Zero external packages

## Getting Started

### Prerequisites

- macOS with Claude Code installed and running in tmux
- Node.js 22+
- tmux (Claude Code sessions must be running inside tmux)
- Xcode 15+ (to build the iOS app)
- iPhone running iOS 17+ (physical device recommended for mic/speaker)

### 1. Start the relay server

```bash
cd relay-server
npm install
npm run dev
```

The server starts on port 3578 and prints a QR code to the terminal.

### 2. Get pairing credentials

The QR code encodes the connection info. You can also retrieve it via HTTP:

```bash
curl http://localhost:3578/pair/json
```

This returns:

```json
{
  "relayUrl": "ws://192.168.1.x:3578/ws",
  "token": "<jwt>",
  "hostname": "your-mac"
}
```

### 3. Connect from your iPhone

Open the Vibe Code app and either scan the QR code displayed in the terminal or enter the relay URL and token manually in the setup screen.

### 4. Use it

1. Select a Claude Code session from the discovered session list
2. Tap the microphone button and speak your command
3. The relay injects your transcribed text into the Claude Code tmux pane
4. When Claude encounters an error, asks a question, or completes a task, you hear it spoken back

## Configuration

All configuration is via environment variables. Defaults work out of the box for standard Claude Code installations.

| Variable | Default | Description |
|----------|---------|-------------|
| `VIBE_PORT` | `3578` | Relay server port |
| `VIBE_HOST` | `0.0.0.0` | Bind address |
| `VIBE_EXTERNAL_URL` | auto-detected | Base URL for pairing (override for Tailscale Funnel) |
| `VIBE_JWT_SECRET_PATH` | `~/.vibe-code/relay-secret.key` | Path to JWT signing key (auto-generated) |
| `VIBE_CLAUDE_PROJECTS_DIR` | `~/.claude/projects` | Where Claude Code stores session JSONL files |
| `VIBE_SESSION_CACHE_TTL_MS` | `5000` | Session discovery cache lifetime |
| `VIBE_WS_PING_INTERVAL_MS` | `30000` | WebSocket keepalive interval |
| `VIBE_WS_AUTH_TIMEOUT_MS` | `10000` | Time allowed to authenticate after connecting |

## Project Structure

```
vibe-code/
  relay-server/
    src/
      index.ts                       Entry point, Fastify + WebSocket wiring
      config.ts                      Environment configuration
      protocol/messages.ts           Zod schemas for all message types
      server/auth.ts                 JWT HS256 authentication
      server/ws-server.ts            Client lifecycle, ping/pong
      server/qr-pairing.ts           GET /pair/json, QR terminal output
      sessions/session-discovery.ts  JSONL dir scanning + tmux correlation
      sessions/jsonl-tailer.ts       chokidar file watch, byte-offset reads
      sessions/tmux-bridge.ts        tmux send-keys input injection
      pipeline/event-classifier.ts   Rule-based event classification
      pipeline/template-summarizer.ts  TTS-friendly text extraction
      pipeline/context-manager.ts    Session context tracking
  ios-app/
    VibeCode/
      Audio/                         STT, TTS, audio session management
      Networking/                    RelayClient, MessageCodec
      Managers/                      VoiceSessionManager, SettingsManager
      Models/                        AppState, VoiceState, AgentEvent
      Views/                         VoiceView, SetupView, SessionPicker
    VibeCode.xcodeproj
```

## License

MIT
