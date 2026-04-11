# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Vibe Code is a voice-first iPhone companion for Claude Code. Speak to your phone, it sends input to an active Claude Code session on your Mac via a WebSocket relay server, and speaks back what Claude is doing. Two components: a Node.js relay server (TypeScript) and a SwiftUI iOS app.

## Commands

### Relay Server

```bash
cd relay-server
npm run dev          # Hot-reload dev server (tsx)
npm run test         # Run vitest (watch mode)
npm run test:run     # Run tests once (72 tests)
npm run typecheck    # tsc --noEmit
npm run build        # Compile to dist/
npm run start        # Run compiled build
```

### iOS App

```bash
cd ios-app
xcodegen generate    # Regenerate .xcodeproj from project.yml (required after project.yml changes)
```

### Deploy to iPhone

```bash
# Build & install (from ios-app/)
xcodebuild build -project VibeCode.xcodeproj -scheme VibeCode -destination "platform=iOS,name=YourPhone" DEVELOPMENT_TEAM=YOUR_TEAM_ID
xcrun devicectl device install app --device YOUR_DEVICE_UUID ~/Library/Developer/Xcode/DerivedData/VibeCode-dxyiuvfrwapildhhspgjfukohbgh/Build/Products/Debug-iphoneos/VibeCode.app
xcrun devicectl device process launch --device YOUR_DEVICE_UUID com.vibecode.app
```

### Relay Server Access

- Local: http://localhost:3578/pair (QR pairing page)
- Public URL (Tailscale Funnel): `https://your-mac.local`
- Start funnel: `tailscale funnel --bg --https=443 http://localhost:3578`

## Architecture

### Data Flow

```
iPhone (voice) → STT → WebSocket → Relay Server → tmux send-keys → Claude Code session
Claude Code → JSONL file writes → chokidar file watcher → event classifier → WebSocket → iPhone → TTS
```

### Relay Server (`relay-server/src/`)

- **`index.ts`** — Fastify entry point, registers WebSocket + HTTP routes
- **`server/ws-server.ts`** — Client lifecycle: auth, ping/pong, message dispatch
- **`server/auth.ts`** — JWT HS256 auth (secret auto-generated at `~/.vibe-code/relay-secret.key`)
- **`sessions/session-discovery.ts`** — Scans `~/.claude/projects/` for JSONL files, correlates with tmux panes to find active Claude Code sessions
- **`sessions/jsonl-tailer.ts`** — Tails JSONL files using chokidar, reads from byte offset, handles partial lines
- **`sessions/tmux-bridge.ts`** — Injects user input via `tmux send-keys`
- **`pipeline/event-classifier.ts`** — Classifies JSONL events into priority levels: interrupt (spoken immediately), queue (batched), silent (logged only)
- **`pipeline/template-summarizer.ts`** — Extracts TTS-friendly text (max 200 chars) from classified events
- **`protocol/messages.ts`** — Zod schemas for all WebSocket message types (upstream + downstream)
- **`server/llm-bridge.ts`** + **`server/tool-endpoints.ts`** — OpenAI-compatible proxy for ElevenLabs conversational AI

### iOS App (`ios-app/VibeCode/`)

**Phase machine**: `setup` → `sessionPicker` → `voice`

- **`Models/AppState.swift`** — Global state (ObservableObject), manages phase transitions and lazy-loads managers
- **`Networking/RelayClient.swift`** — WebSocket client using URLSessionWebSocketTask with exponential backoff reconnect
- **`Networking/MessageCodec.swift`** — Codable enums matching relay's Zod discriminated unions
- **`Managers/VoiceSessionManager.swift`** — Orchestrates STT → relay input → TTS, manages event log (100 events max)
- **`Audio/VoiceProvider.swift`** — Protocol for voice providers
- **`Audio/AppleTTSProvider.swift`** — Built-in AVSpeechSynthesizer
- **`Audio/ElevenLabsVoiceProvider.swift`** — ElevenLabs conversational AI (optional, requires agent ID)
- **`Views/VoiceView.swift`** — Main voice interface with event stream

### WebSocket Protocol

Upstream (phone → relay): `auth`, `input`, `session_list_request`, `attach`, `detach`, `pong`
Downstream (relay → phone): `auth_result`, `session_list`, `agent_event`, `input_ack`, `session_state`, `session_history`, `context_update`, `ping`

### Event Classification Priority

- **Interrupt** (spoken immediately): `AskUserQuestion` tool use, `end_turn` completions, error tool results
- **Queue** (batched): tool_use blocks, intermediate text
- **Silent** (logged): system messages, summaries

## Key Config

- **Relay env vars**: `VIBE_PORT` (3578), `VIBE_HOST` (0.0.0.0), `VIBE_JWT_SECRET_PATH`, `VIBE_CLAUDE_PROJECTS_DIR`, `VIBE_SESSION_CACHE_TTL_MS`
- **iOS bundle**: `com.vibecode.app`, team `YOUR_TEAM_ID`, iOS 17+, arm64
- **ElevenLabs Agent ID**: `YOUR_ELEVENLABS_AGENT_ID`
- **ElevenLabs config**: `~/.vibe-code/elevenlabs.env`
- **ElevenLabs dashboard**: https://elevenlabs.io/app/conversational-ai

## Dependencies

- **Relay**: Fastify v5, `@fastify/websocket` v11, chokidar v4, zod v3.24, jsonwebtoken v9, qrcode — Node 22+, TypeScript 5.7
- **iOS**: SwiftUI + AVFoundation + Speech + Security (zero external Swift deps except optional ElevenLabs SDK v3.0+)

# currentDate
Today's date is 2026-02-22.
