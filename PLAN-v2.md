# Vibe-Code v2: Voice Interface for Claude Code

## Context

Voice-control Claude Code and Codex from an iPhone while walking -- phone locked, headphones on, music ducking like Google Maps. The key innovation is **intelligent summarization**: a priority-tier system that only speaks what matters (questions, errors, milestones) instead of reading back every file diff and tool call.

Building on the existing [vibe-code prototype](https://github.com/trevhud/vibe-code) at `<project-root>` which has a working iOS SSH/tmux client and Mac CLI setup tool.

## Architecture

```
iPhone (locked, headphones)          Your Machine (laptop or Coder)
┌─────────────────────────┐          ┌──────────────────────────────────┐
│  On-device STT           │          │  Relay Server (Node.js)          │
│  (SFSpeechRecognizer)    │          │                                  │
│         │                │          │  ┌─────────────────────────┐     │
│         ▼                │  WebSocket│  │ Session Discovery       │     │
│  ┌─────────────┐         │◄────────►│  │ (tmux + ~/.claude JSONL)│     │
│  │ Relay Client │         │ Tailscale│  └──────────┬──────────────┘     │
│  └──────┬──────┘         │          │             │                    │
│         │                │          │  ┌──────────▼──────────────┐     │
│         ▼                │          │  │ JSONL Tailer / SDK      │     │
│  ┌─────────────┐         │          │  │ (attach or create)      │     │
│  │ TTS Queue   │         │          │  └──────────┬──────────────┘     │
│  │ (priority)  │         │          │             │                    │
│  └──────┬──────┘         │          │  ┌──────────▼──────────────┐     │
│         │                │          │  │ Event Classifier        │     │
│         ▼                │          │  │ (rule-based tiers)      │     │
│  ┌─────────────┐         │          │  └──────────┬──────────────┘     │
│  │ TTSProvider │         │          │             │                    │
│  │ (Kokoro/    │         │          │  ┌──────────▼──────────────┐     │
│  │  Apple/DI)  │         │          │  │ Haiku Summarizer        │     │
│  └─────────────┘         │          │  │ (~$0.04/hr)             │     │
│                          │          │  └─────────────────────────┘     │
│  AVAudioSession          │          │                                  │
│  (.duckOthers)           │          │  tmux send-keys (input inject)   │
└─────────────────────────┘          └──────────────────────────────────┘
```

**Two modes for agent interaction:**
- **Attach mode**: Hop into an existing Claude Code session. Tail its JSONL transcript (`~/.claude/projects/{path}/{session}.jsonl`) for structured events. Inject input via `tmux send-keys`.
- **SDK mode**: Start a new session via Claude Agent SDK. Full structured streaming events.

Both modes feed through the same pipeline: classify → summarize → speak.

## Summarization Strategy: Subscription-Only (No Per-Token API Costs)

All inference uses the user's Max subscription ($200/mo). Three layers work together:

### Layer 1: MCP Tool -- `voice_update` (Claude-initiated)

Register an MCP tool on the relay server that Claude Code calls proactively:

```
Tool: voice_update
Input: { text: string, priority: "interrupt" | "queue" }
```

Claude already knows what's important. A CLAUDE.md instruction tells it to call `voice_update` for high-level status updates, questions, errors, and milestones. Claude becomes its own summarizer -- no external LLM call needed.

**CLAUDE.md addition** (injected when voice mode is active):
```
## Voice Mode Active
The user is listening via voice on their phone. Call the `voice_update` tool to speak to them.
- Call with priority "interrupt" for: questions, errors, task completion, permission needs
- Call with priority "queue" for: plan summaries, milestones, test results
- Keep messages to 1-2 sentences, plain English, no code or file paths
- Do NOT call voice_update for routine file reads, edits, or searches
```

### Layer 2: Claude Code Hooks (Automatic catch-all)

PostToolUse hooks on the relay server detect important events that Claude didn't announce:

```yaml
# Hooks registered by relay server
PostToolUse:
  - matcher: { tool_name: "Bash" }
    # Check exit code, detect test results/errors
  - matcher: { tool_name: "Write" }
    # New file creation
```

Hook scripts classify events and send them to the relay's WebSocket pipeline. Uses rule-based templates (no LLM):
- Test result: regex for pass/fail → "Tests: 4 passed, 0 failed"
- Bash error: non-zero exit → "Command failed: {first line of stderr}"
- File created: → "Created {filename}"

### Layer 3: Fallback `claude -p` (Rare, complex batches only)

When multiple QUEUE events accumulate and templates aren't enough, use:
```bash
claude -p "Summarize in one sentence: ..." --model claude-haiku-4-5-20251001
```
This routes through the Max subscription. Expected usage: <5 calls/hour.

### Why This Works

| Layer | When | Cost | Latency |
|-------|------|------|---------|
| MCP tool | Claude proactively updates you | $0 (subscription) | ~0ms (inline) |
| Hooks + templates | Catches events Claude doesn't announce | $0 (rule-based) | <10ms |
| `claude -p` fallback | Complex multi-event batches | $0 (subscription) | ~2-3s |

## Priority Tiers

| Tier | Behavior | Events |
|------|----------|--------|
| **INTERRUPT** | Stop current speech, speak immediately | Questions (`AskUserQuestion`), errors, task completion, permission requests |
| **QUEUE** | Batch for 5s, summarize, speak at pause | Test results, file creation, git commits, plan announcements |
| **SILENT** | Never spoken, visual log only | File reads, edits, grep results, intermediate reasoning |

**Example**: Claude edits 3 files and runs tests → calls `voice_update("Fixed token validation in auth. All tests passing.", "queue")` → you hear it.

## Key Technical Decisions

- **Summarization**: 3-layer hybrid (MCP tool + hooks + `claude -p` fallback). All subscription-based, zero per-token API costs.
- **TTS**: Protocol-based DI (`TTSProvider`). Ship with Kokoro (mlx-audio-swift, Apache 2.0, 8/10 quality) + Apple Premium fallback. Swap in new models (Nvidia PersonaPlex-7B, etc.) by implementing the protocol.
- **STT**: `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true` (iOS 17+). Upgrade path to `SpeechAnalyzer` on iOS 26.
- **Audio ducking**: `AVAudioSession(.playAndRecord, options: [.duckOthers, .allowBluetooth])` -- music fades when TTS speaks, restores after.
- **Background**: `audio` background mode + silent audio keepalive. Headphone button (MPRemoteCommandCenter) for push-to-talk when locked.
- **Session attachment**: Tail JSONL files (structured events from existing sessions) + `tmux send-keys` for input. No terminal output parsing.
- **Relay server**: Node.js/TypeScript (Claude Agent SDK is TS-native). Deployable on laptop or Coder. Also acts as MCP server exposing `voice_update` tool.
- **Networking**: WebSocket over Tailscale. JWT auth from QR code pairing.

## Project Structure

```
vibe-code/
├── relay-server/                      # NEW: Node.js relay
│   ├── package.json
│   ├── tsconfig.json
│   ├── Dockerfile                     # For Coder deployment
│   └── src/
│       ├── index.ts                   # Entry: HTTP + WebSocket server
│       ├── config.ts                  # Environment config
│       ├── server/
│       │   ├── ws-server.ts           # WebSocket handler (phone connections)
│       │   └── auth.ts               # JWT token auth
│       ├── sessions/
│       │   ├── session-discovery.ts   # Scan tmux + ~/.claude/projects/
│       │   ├── session-manager.ts     # Active session lifecycle
│       │   ├── jsonl-tailer.ts        # Tail JSONL transcripts (attach mode)
│       │   ├── tmux-bridge.ts         # send-keys, capture-pane
│       │   └── codex-bridge.ts        # Codex ~/.codex/history.jsonl
│       ├── agents/
│       │   └── sdk-session.ts         # Claude Agent SDK wrapper (new sessions)
│       ├── pipeline/
│       │   ├── event-classifier.ts    # Rule-based priority tiers
│       │   ├── event-batcher.ts       # 5s batching for QUEUE tier
│       │   ├── template-summarizer.ts # Rule-based templates (test results, errors, etc.)
│       │   ├── cli-summarizer.ts      # Fallback: claude -p for complex batches
│       │   └── types.ts              # Shared types
│       ├── mcp/
│       │   └── voice-update-tool.ts   # MCP tool: voice_update (Claude-initiated)
│       ├── hooks/
│       │   └── post-tool-use.ts       # Hook scripts for automatic event detection
│       └── protocol/
│           └── messages.ts            # WebSocket message schemas
│
├── ios-app/                           # EVOLVED: Voice-first iOS app
│   ├── Package.swift                  # Updated deps (remove NIO/SSH, add mlx-audio)
│   └── VibeCode/
│       ├── VibeCodeApp.swift          # Audio session setup on launch
│       ├── Info.plist                 # Background modes, mic, speech
│       │
│       ├── Audio/                     # NEW
│       │   ├── AudioSessionManager.swift    # AVAudioSession + ducking lifecycle
│       │   ├── TTSProvider.swift            # Protocol (DI abstraction)
│       │   ├── KokoroTTSProvider.swift      # mlx-audio-swift
│       │   ├── AppleTTSProvider.swift       # AVSpeechSynthesizer fallback
│       │   ├── TTSQueueManager.swift        # Priority queue, interrupt/batch
│       │   └── STTManager.swift             # SFSpeechRecognizer on-device
│       │
│       ├── Networking/                # NEW (replaces SSH)
│       │   ├── RelayClient.swift            # WebSocket to relay server
│       │   ├── MessageCodec.swift           # Encode/decode protocol messages
│       │   └── ReconnectionManager.swift    # Exponential backoff
│       │
│       ├── Managers/                  # EVOLVED
│       │   ├── SettingsManager.swift        # REUSE (95%) - Keychain + UserDefaults
│       │   ├── VoiceSessionManager.swift    # NEW: Orchestrates STT→relay→TTS
│       │   └── NotificationManager.swift    # NEW: APNs fallback
│       │
│       ├── Models/                    # EVOLVED
│       │   ├── AppState.swift               # REWRITE: Voice-first state machine
│       │   ├── ConnectionProfile.swift      # ADAPT: relay URL instead of SSH
│       │   ├── Message.swift                # ADAPT: Add priority tiers
│       │   ├── AgentEvent.swift             # NEW: Structured events from relay
│       │   └── VoiceState.swift             # NEW: listening/speaking/idle
│       │
│       └── Views/                     # EVOLVED
│           ├── VoiceView.swift              # NEW: Primary voice UI
│           ├── WaveformView.swift           # NEW: Audio visualization
│           ├── SessionPickerView.swift      # ADAPT: Show discovered sessions
│           ├── QRScannerView.swift          # REUSE (100%)
│           ├── SetupView.swift              # ADAPT: Relay pairing flow
│           ├── SettingsView.swift           # ADAPT: TTS provider picker
│           └── EventLogView.swift           # NEW: Scrollable event history
│
├── mac-app/                           # KEEP: Setup utility
│   └── Sources/VibeCodeCLI/
│       ├── main.swift                 # Add 'relay' subcommand
│       ├── SetupManager.swift         # REUSE: Tailscale + SSH setup
│       ├── SessionManager.swift       # REUSE: tmux session ops
│       ├── ConnectionManager.swift    # ADAPT: QR includes relay URL
│       ├── HealthMonitor.swift        # REUSE
│       └── ProcessRunner.swift        # REUSE
│
└── README.md
```

## Reusable Files from v1

| File | Path | Reuse |
|------|------|-------|
| SettingsManager | `ios-app/VibeCode/Managers/SettingsManager.swift` | 95% -- add relay token storage |
| QRScannerView | `ios-app/VibeCode/Views/QRScannerView.swift` | 100% -- use as-is |
| ConnectionProfile | `ios-app/VibeCode/Models/ConnectionProfile.swift` | 70% -- change host/port to relayUrl |
| Message | `ios-app/VibeCode/Models/Message.swift` | 70% -- add priority enum |
| SessionPickerView | `ios-app/VibeCode/Views/SessionPickerView.swift` | 80% -- adapt for discovered sessions |
| SetupManager | `mac-app/.../SetupManager.swift` | 90% -- add relay server start |
| SessionManager | `mac-app/.../SessionManager.swift` | 90% -- port tmux ops to TS too |
| HealthMonitor | `mac-app/.../HealthMonitor.swift` | 90% |
| ProcessRunner | `mac-app/.../ProcessRunner.swift` | 100% |

## Build Phases

### Phase 1: MVP Voice Loop (Weeks 1-2)
**Goal**: Speak a command → arrives at existing Claude Code session → hear errors/questions back.

**Relay server:**
- [ ] Project scaffold (package.json, tsconfig, Dockerfile)
- [ ] WebSocket server with JWT auth (`ws-server.ts`, `auth.ts`)
- [ ] Session discovery: scan `~/.claude/projects/` + `tmux list-sessions` (`session-discovery.ts`)
- [ ] JSONL tailer: tail transcript files for new events (`jsonl-tailer.ts`)
- [ ] tmux bridge: `send-keys` for input injection (`tmux-bridge.ts`)
- [ ] Basic event classifier: INTERRUPT only (questions, errors) (`event-classifier.ts`)
- [ ] Template summarizer: rule-based text for detected events (`template-summarizer.ts`)
- [ ] QR code pairing endpoint (print QR with relay URL + JWT)

**iOS app:**
- [ ] Strip SSH/NIO dependencies from Package.swift
- [ ] WebSocket client to relay (`RelayClient.swift`, `MessageCodec.swift`)
- [ ] STT: `SFSpeechRecognizer` with on-device recognition (`STTManager.swift`)
- [ ] TTS: `AppleTTSProvider` only (AVSpeechSynthesizer, zero setup) (`TTSProvider.swift`, `AppleTTSProvider.swift`)
- [ ] Audio session: `.playAndRecord` + `.duckOthers` (`AudioSessionManager.swift`)
- [ ] Voice-first AppState rewrite (`AppState.swift`, `VoiceState.swift`)
- [ ] Minimal VoiceView: mic button + status text (`VoiceView.swift`)
- [ ] QR scanning for pairing (reuse `QRScannerView.swift`)
- [ ] Adapted `SettingsManager.swift` for relay credentials

**Verify**: Speak "fix the failing test" → relay discovers session → sends to tmux → Claude responds → error/question events read back via Apple TTS.

### Phase 2: MCP + Hooks Summarization (Week 3)
**Goal**: Claude tells you what matters via `voice_update` tool + hooks catch the rest.

- [ ] MCP server: `voice_update` tool exposed to Claude Code (`voice-update-tool.ts`)
- [ ] CLAUDE.md injection: voice mode instructions when session is active
- [ ] PostToolUse hooks: detect test results, errors, file creation (`post-tool-use.ts`)
- [ ] Full event classifier: all three tiers (`event-classifier.ts`)
- [ ] Event batcher: 5s window for QUEUE tier (`event-batcher.ts`)
- [ ] `claude -p` fallback summarizer for complex batches (`cli-summarizer.ts`)
- [ ] `TTSQueueManager.swift`: priority queue, INTERRUPT cuts through, QUEUE batches
- [ ] `AgentEvent.swift` model with priority + summary
- [ ] `EventLogView.swift`: scrollable visual log of all events (including SILENT)
- [ ] `WaveformView.swift`: audio level visualization
- [ ] Connection auto-reconnect (`ReconnectionManager.swift`)

**Verify**: Claude edits files and runs tests → calls `voice_update("Fixed the auth bug. Tests passing.", "queue")` → you hear it. Hook also catches test results independently.

### Phase 3: Kokoro + Background (Week 4)
**Goal**: Works with phone locked in pocket, great voice quality.

- [ ] Kokoro TTS via mlx-audio-swift (`KokoroTTSProvider.swift`)
- [ ] TTS provider switching in Settings
- [ ] Audio ducking lifecycle: activate before speak, deactivate after
- [ ] Background audio: silent keepalive when app enters background
- [ ] `MPRemoteCommandCenter` for headphone push-to-talk when locked
- [ ] APNs push notifications for INTERRUPT events when app suspended (`NotificationManager.swift`)
- [ ] Info.plist: `UIBackgroundModes` (audio, fetch, remote-notification)

**Verify**: Lock phone, play music, walk away → music ducks when Claude speaks → press AirPod to respond → music resumes.

### Phase 4: SDK Mode + Codex (Week 5)
**Goal**: Create new sessions from phone, support Codex.

- [ ] Claude Agent SDK integration (`sdk-session.ts`)
- [ ] "New session" in session picker
- [ ] Codex CLI bridge: tail `~/.codex/history.jsonl` (`codex-bridge.ts`)
- [ ] Permission/approval forwarding to phone
- [ ] Session creation and lifecycle management

### Phase 5: Polish + Coder (Week 6)
**Goal**: Production-ready, works on Coder.

- [ ] Dockerfile for relay server (Coder deployment)
- [ ] Coder workspace setup docs (Tailscale in workspace)
- [ ] Kokoro model download/cache management
- [ ] Settings: TTS provider picker, voice selection, priority tuning
- [ ] Error handling and edge cases
- [ ] README and setup guide updates

### Future
- SpeechAnalyzer (iOS 26) for better background STT
- New TTS models via protocol (Nvidia PersonaPlex-7B, etc.)
- Multi-relay: connect to laptop + Coder simultaneously
- Haptic patterns for different event priorities
- Conversation history with search

## Verification Plan

1. **Phase 1 smoke test**: `vibe-code setup` on Mac → `cd relay-server && npm start` → scan QR on phone → select existing Claude Code session → speak "what files are in this directory" → hear response
2. **Summarization test**: Trigger a multi-step Claude Code task (edit + test) → verify only 1-2 summary sentences spoken, not full output
3. **Audio ducking test**: Play Spotify → trigger TTS → verify music volume drops and restores
4. **Background test**: Lock phone → have Claude encounter an error → verify audio plays through headphones
5. **Coder test**: Deploy relay Dockerfile to Coder workspace → pair phone → verify attach works over Tailscale
