# Vibe Code iOS App

Voice-first companion for Claude Code. Speak commands, hear back what matters.

## Overview

The iPhone app connects to a relay server running on your Mac via WebSocket. It uses on-device speech recognition to transcribe your voice commands, sends them to Claude Code via the relay, and speaks back errors, questions, and completions using text-to-speech.

## Architecture

```
VibeCode/
├── VibeCodeApp.swift                    # Entry point, audio session setup
├── ContentView.swift                    # Routes by AppState.phase
├── Models/
│   ├── AppState.swift                   # Phase machine: setup → sessionPicker → voice
│   ├── ConnectionProfile.swift          # relayUrl + token + hostname
│   ├── VoiceState.swift                 # idle, listening, processing, speaking
│   ├── AgentEvent.swift                 # Priority + category + summary
│   └── Message.swift                    # Chat message model
├── Networking/
│   ├── RelayClient.swift                # URLSessionWebSocketTask + auto-reconnect
│   └── MessageCodec.swift              # Codable enums matching relay Zod schemas
├── Audio/
│   ├── STTManager.swift                 # SFSpeechRecognizer (on-device)
│   ├── TTSProvider.swift                # Protocol for TTS backends
│   ├── AppleTTSProvider.swift           # AVSpeechSynthesizer (premium voice)
│   └── AudioSessionManager.swift        # AVAudioSession configuration
├── Managers/
│   ├── VoiceSessionManager.swift        # STT → relay → TTS orchestration
│   └── SettingsManager.swift            # Keychain + UserDefaults
└── Views/
    ├── VoiceView.swift                  # Main view: mic button, state, event log
    ├── SetupView.swift                  # QR scan + manual entry
    ├── QRScannerView.swift              # Camera-based QR scanning
    ├── SessionPickerView.swift          # Choose from discovered sessions
    ├── ManualSetupView.swift            # Relay URL + token input
    └── SettingsView.swift               # Connection info, reconnect, reset
```

## Key Components

### RelayClient
`URLSessionWebSocketTask`-based WebSocket client with:
- Exponential backoff reconnect (1s → 2s → 4s → ... → 30s max)
- Auto pong reply to server pings
- `PassthroughSubject<DownstreamMessage, Never>` for event stream
- No reconnect on auth failure or intentional disconnect

### VoiceSessionManager
Orchestrates the voice loop:
1. **Start listening** → activates STT, stops TTS if speaking
2. **Stop and send** → gets transcript, sends `input` message via relay
3. **Receive agent_event** → if interrupt priority, stop STT, speak via TTS

### STTManager
On-device speech recognition using `SFSpeechRecognizer`:
- `requiresOnDeviceRecognition` when supported
- Audio engine tap on input node (bus 0, buffer 1024)
- Published `transcript` updated with partial results

### AppleTTSProvider
`AVSpeechSynthesizer` with async/await:
- Premium > enhanced > default English voice selection
- Rate 0.5 for clarity
- Handles interruption: stops current speech before starting new

## Dependencies

**Zero external packages.** Everything uses built-in iOS 17+ APIs:
- `URLSessionWebSocketTask` — WebSocket
- `SFSpeechRecognizer` — Speech-to-text
- `AVSpeechSynthesizer` — Text-to-speech
- `AVAudioSession` — Audio routing
- `AVFoundation` — Camera (QR scanning)
- `Security` — Keychain

## Building

```bash
open VibeCode.xcodeproj
# Select your iPhone or simulator
# Build and run (Cmd+R)
```

Requires:
- Xcode 15+
- iOS 17+ deployment target
- Physical device for mic/speaker testing

## Permissions

The app requests:
- **Camera** — QR code scanning
- **Microphone** — Voice input
- **Speech Recognition** — On-device transcription
