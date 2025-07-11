# Vibe Code

Continue your Claude Code conversations seamlessly from laptop to iPhone, anywhere in the world.

## What is Vibe Code?

Vibe Code bridges the gap between your laptop development environment and mobile accessibility. Start a coding session with Claude Code on your Mac, then pull out your iPhone anywhere and continue the exact same conversation with full context.

## Project Structure

```
vibe-code/
├── README.md                 # This file
├── SETUP_GUIDE.md           # User setup instructions
├── mac-app/                 # macOS setup and management app
│   ├── Sources/
│   ├── Package.swift
│   └── README.md
├── ios-app/                 # iPhone app for remote access
│   ├── VibeCode.xcodeproj
│   ├── VibeCode/
│   └── README.md
└── docs/                    # Additional documentation
    ├── ARCHITECTURE.md
    └── DEVELOPMENT.md
```

## Quick Start

### For Users
1. `brew install vibe-code`
2. `vibe-code setup`
3. Download Vibe Code iPhone app
4. Scan QR code
5. Continue your Claude Code sessions anywhere!

### For Developers
See individual README files in `mac-app/` and `ios-app/` directories.

## Key Features

- **Seamless Continuity**: Exact same conversation and context across devices
- **Global Access**: Works anywhere with internet connection via Tailscale VPN
- **Zero Setup Friction**: Automated Mac app handles all configuration
- **Secure**: End-to-end encrypted, no data leaves your devices
- **Always Available**: Persistent sessions even when laptop sleeps

## Architecture

- **Mac App**: Swift command-line tool for setup and session management
- **iPhone App**: Native iOS app with SSH client and optimized conversation UI
- **Connection**: Tailscale VPN for secure global connectivity
- **Session Management**: tmux for persistent Claude Code sessions

## Development Status

🚧 **In Active Development** 🚧

- [x] Project structure and documentation
- [ ] Mac app implementation
- [ ] iPhone app implementation
- [ ] End-to-end testing
- [ ] App Store submission

## Contributing

This project is currently in initial development. Please see individual app directories for development guidelines once implementation begins.

## License

[To be determined]