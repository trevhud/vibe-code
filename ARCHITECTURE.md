# Vibe Code v2 Architecture

## Overview

Vibe Code is a voice-first mobile companion for Claude Code. A relay server on the Mac bridges an iPhone app to existing Claude Code sessions, enabling hands-free voice interaction while walking, commuting, or away from the desk.

## System Diagram

```mermaid
graph TB
    subgraph iPhone["iPhone (iOS 17+)"]
        direction TB
        UI[VoiceView<br/>Mic button + state indicator]
        ASM[AppState<br/>Phase machine: setup → sessionPicker → voice]
        VSM[VoiceSessionManager<br/>Orchestrates STT → relay → TTS]
        STT[STTManager<br/>SFSpeechRecognizer<br/>on-device recognition]
        TTS[AppleTTSProvider<br/>AVSpeechSynthesizer<br/>premium voice]
        AUD[AudioSessionManager<br/>.playAndRecord + duckOthers]
        RC[RelayClient<br/>URLSessionWebSocketTask<br/>exponential backoff reconnect]
        MC[MessageCodec<br/>Codable ↔ JSON]

        UI --> ASM
        ASM --> VSM
        VSM --> STT
        VSM --> TTS
        VSM --> RC
        TTS --> AUD
        STT --> AUD
        RC --> MC
    end

    subgraph Mac["Mac (Development Machine)"]
        subgraph Relay["Relay Server :3578"]
            direction TB
            FAS[Fastify HTTP + WebSocket]
            WSS[WsServer<br/>client lifecycle, ping/pong]
            AUTH[JWT Auth<br/>HS256, auto-generated secret]
            QR[QR Pairing<br/>GET /pair/json]
            SD[SessionDiscovery<br/>scan ~/.claude/projects/<br/>+ tmux list-panes]
            JT[JsonlTailer<br/>chokidar + byte-offset reads]
            TB[TmuxBridge<br/>send-keys -l]
            EC[EventClassifier<br/>rule-based: question, error, completion]
            TS2[TemplateSummarizer<br/>TTS-friendly text]

            FAS --> WSS
            FAS --> QR
            WSS --> AUTH
            WSS --> SD
            WSS --> JT
            WSS --> TB
            JT --> EC --> TS2
        end

        subgraph Claude["Claude Code"]
            JSONL["JSONL Files<br/>~/.claude/projects/-encoded-path/*.jsonl"]
            TMUX["tmux Sessions<br/>Claude runs as version (e.g. 2.1.42)"]
        end

        JT -.->|"chokidar watch"| JSONL
        TB -.->|"tmux send-keys"| TMUX
        SD -.->|"readdir + stat"| JSONL
        SD -.->|"tmux list-panes -a"| TMUX
    end

    RC <-->|"WebSocket (ws://)"| FAS
    TS2 -->|"agent_event → TTS"| WSS

    style iPhone fill:#e8f4fd,stroke:#2196F3
    style Relay fill:#fff3e0,stroke:#FF9800
    style Claude fill:#e8f5e9,stroke:#4CAF50
```

## Data Flow

### Voice Command (Phone → Claude Code)

```mermaid
sequenceDiagram
    participant User
    participant STT as STTManager
    participant VSM as VoiceSessionManager
    participant RC as RelayClient
    participant WS as WsServer
    participant TB as TmuxBridge
    participant CC as Claude Code

    User->>STT: Tap mic + speak
    STT->>VSM: transcript: "list files in src"
    VSM->>RC: {type: "input", text: "list files in src"}
    RC->>WS: WebSocket frame
    WS->>TB: sendInput(tmuxSession, text)
    TB->>CC: tmux send-keys -l "list files in src" Enter
    CC-->>WS: input_ack {success: true}
    WS-->>RC: input_ack
    RC-->>VSM: ack received
```

### Event Notification (Claude Code → Phone)

```mermaid
sequenceDiagram
    participant CC as Claude Code
    participant JSONL as JSONL File
    participant JT as JsonlTailer
    participant EC as EventClassifier
    participant TS as TemplateSummarizer
    participant WS as WsServer
    participant RC as RelayClient
    participant VSM as VoiceSessionManager
    participant TTS as TTSProvider

    CC->>JSONL: Write assistant message
    JT->>JSONL: chokidar: file changed
    JT->>EC: parsed JSONL record
    EC->>EC: AskUserQuestion? → interrupt/question
    EC->>TS: ClassifiedEvent
    TS->>TS: Extract question text
    TS->>WS: agent_event {priority, category, summary}
    WS->>RC: WebSocket frame
    RC->>VSM: downstream message
    VSM->>TTS: speak("Which approach?")
    TTS->>TTS: AVSpeechSynthesizer
```

## Core Components

### Relay Server (`relay-server/`)

| Component | File | Purpose |
|-----------|------|---------|
| Entry point | `src/index.ts` | Fastify + WebSocket wiring, message routing |
| Config | `src/config.ts` | Port, paths, timeouts from env |
| Protocol | `src/protocol/messages.ts` | Zod schemas for all WebSocket messages |
| Auth | `src/server/auth.ts` | JWT HS256, secret auto-generation |
| WS Server | `src/server/ws-server.ts` | Client lifecycle, auth flow, ping/pong |
| QR Pairing | `src/server/qr-pairing.ts` | GET /pair/json, QR terminal output |
| Discovery | `src/sessions/session-discovery.ts` | Scan JSONL dirs + tmux correlation |
| JSONL Tailer | `src/sessions/jsonl-tailer.ts` | chokidar watch, byte-offset reads |
| tmux Bridge | `src/sessions/tmux-bridge.ts` | send-keys, capture-pane |
| Classifier | `src/pipeline/event-classifier.ts` | Rule-based event → priority mapping |
| Summarizer | `src/pipeline/template-summarizer.ts` | Human/TTS-friendly text extraction |

### iOS App (`ios-app/`)

| Component | File | Purpose |
|-----------|------|---------|
| App State | `Models/AppState.swift` | Phase machine: setup → sessionPicker → voice |
| Relay Client | `Networking/RelayClient.swift` | URLSessionWebSocketTask + auto-reconnect |
| Message Codec | `Networking/MessageCodec.swift` | Codable enums matching Zod schemas |
| STT | `Audio/STTManager.swift` | SFSpeechRecognizer, on-device |
| TTS | `Audio/AppleTTSProvider.swift` | AVSpeechSynthesizer, async/await |
| Audio Session | `Audio/AudioSessionManager.swift` | .playAndRecord, duck others |
| Voice Manager | `Managers/VoiceSessionManager.swift` | STT → relay → TTS orchestration |
| Voice View | `Views/VoiceView.swift` | Mic button, state indicator, event log |

## WebSocket Protocol

### Phone → Relay (Upstream)

| Type | Fields | Purpose |
|------|--------|---------|
| `auth` | `token` | JWT from QR scan |
| `input` | `sessionId`, `text` | Transcribed speech → tmux |
| `session_list_request` | — | Request available sessions |
| `attach` | `sessionId` | Start tailing a session's JSONL |
| `detach` | — | Stop tailing |
| `pong` | — | Keepalive response |

### Relay → Phone (Downstream)

| Type | Fields | Purpose |
|------|--------|---------|
| `auth_result` | `success`, `error?` | Auth response |
| `session_list` | `sessions[]` | Available Claude Code sessions |
| `agent_event` | `sessionId`, `priority`, `category`, `summary`, `timestamp` | Event to speak/display |
| `input_ack` | `sessionId`, `success`, `error?` | Input injection result |
| `session_state` | `sessionId`, `state` | Session lifecycle changes |
| `ping` | — | Keepalive |

## Event Classification

```mermaid
flowchart TD
    JSONL[JSONL Record] --> TYPE{record.type?}

    TYPE -->|assistant| ASK{Has AskUserQuestion<br/>tool_use?}
    ASK -->|yes| Q[INTERRUPT / question]
    ASK -->|no| ENDTURN{stop_reason =<br/>end_turn?}
    ENDTURN -->|yes + text-only| COMP[INTERRUPT / completion]
    ENDTURN -->|no or has tool_use| SILENT1[null — silent]

    TYPE -->|user| TOOL{Has tool_result?}
    TOOL -->|is_error = true| ERR1[INTERRUPT / error]
    TOOL -->|content matches<br/>error pattern| ERR2[INTERRUPT / error]
    TOOL -->|no error| SILENT2[null — silent]

    TYPE -->|system/summary| SILENT3[null — silent]

    style Q fill:#ff6b6b,color:white
    style ERR1 fill:#ff6b6b,color:white
    style ERR2 fill:#ff6b6b,color:white
    style COMP fill:#51cf66,color:white
    style SILENT1 fill:#868e96,color:white
    style SILENT2 fill:#868e96,color:white
    style SILENT3 fill:#868e96,color:white
```

### Error Patterns

The classifier detects errors by checking the first line of tool result content for:
- `exit code N` (where N ≠ 0)
- `error:`, `fatal:`, `panic:`, `traceback`, `exception:`

## Security

| Layer | Mechanism |
|-------|-----------|
| Authentication | JWT HS256, auto-generated 64-byte secret at `~/.vibe-code/relay-secret.key` |
| Token lifecycle | No expiry — revoke by regenerating the secret |
| Transport | WebSocket over local network (LAN or Tailscale) |
| Auth timeout | 10s to authenticate after connecting, else disconnected |
| Credential storage | iOS Keychain for relay token, UserDefaults for relay URL |

## Session Discovery

1. Scan `~/.claude/projects/` for subdirectories
2. Decode encoded dir names: `-Users-username-Code-project` → `/Users/username/Code/project`
3. Find most recent `.jsonl` file per project directory
4. Correlate with `tmux list-panes -a` — Claude Code shows as version number (e.g. `2.1.42`) in `pane_current_command`
5. Return sorted: active sessions first, then by last activity descending
6. Cache results for 5 seconds

## Voice State Machine

```mermaid
stateDiagram-v2
    [*] --> idle
    idle --> listening: Tap mic
    listening --> processing: Tap stop / send
    processing --> idle: input_ack received
    idle --> speaking: INTERRUPT agent_event
    listening --> speaking: INTERRUPT agent_event
    speaking --> idle: TTS finished
    speaking --> idle: Tap to stop
```

## Tech Stack

### Relay Server
- **Runtime**: Node.js 22, ESM
- **HTTP**: Fastify v5
- **WebSocket**: @fastify/websocket (wraps ws)
- **Validation**: Zod 3.x with discriminatedUnion
- **Auth**: jsonwebtoken (HS256)
- **File watching**: chokidar
- **Dev**: TypeScript 5.x strict, tsx for hot-reload, vitest

### iOS App
- **UI**: SwiftUI (iOS 17+)
- **WebSocket**: URLSessionWebSocketTask (built-in)
- **Speech**: SFSpeechRecognizer (on-device)
- **TTS**: AVSpeechSynthesizer (premium voice)
- **Audio**: AVAudioSession (.playAndRecord)
- **Storage**: Keychain + UserDefaults
- **Dependencies**: Zero external packages
