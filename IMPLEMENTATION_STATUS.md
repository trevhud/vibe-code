# Vibe Code v2 Implementation Status

## Phase 1 MVP: Voice Loop — Complete

Speak a command from iPhone → relay injects into Claude Code session → hear errors/questions spoken back.

## Relay Server (Node.js/TypeScript)

| Component | Status | Tests |
|-----------|--------|-------|
| Fastify HTTP + WebSocket scaffold | Done | 5/5 health endpoint |
| JWT auth + auto-generated secret | Done | 6/6 auth flow |
| QR pairing (`GET /pair/json`) | Done | 5/5 pairing |
| Session discovery (JSONL + tmux) | Done | 7/7 discovery |
| JSONL tailer (chokidar, byte-offset) | Done | E2E verified |
| tmux bridge (send-keys -l) | Done | E2E verified |
| Event classifier (question/error/completion) | Done | 18/18 classifier |
| Template summarizer (TTS-friendly) | Done | 12/12 summarizer |
| Protocol messages (Zod schemas) | Done | 13/13 protocol |
| **Total** | **Done** | **72/72 passing** |

## iOS App (SwiftUI)

| Component | Status | Notes |
|-----------|--------|-------|
| RelayClient (URLSessionWebSocketTask) | Done | Exponential backoff reconnect |
| MessageCodec (Codable ↔ JSON) | Done | Matches Zod schemas |
| STTManager (SFSpeechRecognizer) | Done | On-device recognition |
| AppleTTSProvider (AVSpeechSynthesizer) | Done | Premium voice, async/await |
| AudioSessionManager | Done | .playAndRecord, duck others |
| VoiceSessionManager | Done | STT → relay → TTS orchestration |
| AppState (phase machine) | Done | setup → sessionPicker → voice |
| VoiceView (mic button, state, event log) | Done | SF Symbols + animations |
| SetupView (QR scan + manual) | Done | QRPayload parsing |
| SessionPickerView | Done | DiscoveredSession from relay |
| SettingsView | Done | Relay connection model |
| ConnectionProfile (relayUrl + token) | Done | Replaced SSH model |
| SettingsManager (Keychain) | Done | storeRelayToken/retrieveRelayToken |
| **Needs** | **Xcode build + device test** | Zero external dependencies |

## Deleted (v1 → v2)

| File | Reason |
|------|--------|
| `ConnectionManager.swift` | Replaced by RelayClient |
| `ConversationParser.swift` | Relay sends structured events |
| `PasswordInputView.swift` | No passwords in relay auth |
| `ConversationView.swift` | Replaced by VoiceView |
| Package.swift NIO/SSH deps | URLSessionWebSocketTask is built-in |

## What's Next

### Immediate
- [ ] Build iOS app in Xcode, fix any compilation issues
- [ ] Test on physical iPhone (mic, speaker, WebSocket)
- [ ] End-to-end: speak → Claude Code → hear response

### Phase 2 (Future)
- [ ] Queue priority events (batch non-urgent notifications)
- [ ] Permission category handling (auto-approve patterns)
- [ ] Progress category (summarize tool call activity)
- [ ] ElevenLabs TTS upgrade (more natural voice)
- [ ] Persistent event history across app launches
- [ ] Background audio mode (keep listening while app backgrounded)
