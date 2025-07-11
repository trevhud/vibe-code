# Vibe Code iPhone App

Native iOS application for continuing Claude Code conversations remotely via secure SSH connection.

## Overview

The iPhone app provides a mobile-optimized interface for interacting with Claude Code sessions running on your Mac. It connects securely through Tailscale VPN and maintains full conversation context.

## Features

### Core Functionality
- **QR Code Pairing**: Instant setup by scanning QR code from Mac app
- **SSH Connection**: Secure connection to Mac via Tailscale
- **Session Continuity**: Seamless continuation of Claude Code conversations
- **Real-time Sync**: Live conversation updates and input handling

### User Interface
- **Conversation View**: Mobile-optimized chat interface showing Claude interactions
- **Input Handling**: Optimized keyboard and input for coding discussions
- **Connection Status**: Visual indicators for connection health
- **Settings**: Connection management and troubleshooting

### Security
- **Secure Storage**: SSH credentials stored in iOS Keychain
- **Auto-reconnect**: Automatic reconnection handling
- **Session Validation**: Secure session authentication
- **Network Encryption**: All traffic encrypted via Tailscale VPN

## Architecture

### Core Components

1. **ConnectionManager**: Handles SSH connection and session management
2. **ConversationView**: Main chat interface for Claude interactions
3. **SettingsManager**: User preferences and connection configuration
4. **KeychainManager**: Secure credential storage
5. **QRScannerView**: QR code scanning for setup

### App Structure
```
VibeCode/
├── App/
│   ├── VibeCodeApp.swift          # Main app entry point
│   └── ContentView.swift          # Root view controller
├── Views/
│   ├── ConversationView.swift     # Main chat interface
│   ├── SetupView.swift            # Initial setup and QR scanning
│   ├── SettingsView.swift         # Connection settings
│   └── Components/               # Reusable UI components
├── Managers/
│   ├── ConnectionManager.swift    # SSH and session handling
│   ├── KeChainManager.swift      # Secure storage
│   └── SettingsManager.swift     # User preferences
├── Models/
│   ├── ConnectionProfile.swift    # Connection configuration
│   ├── Message.swift             # Chat message model
│   └── AppState.swift            # App state management
└── Resources/
    ├── Info.plist               # App configuration
    └── Assets.xcassets          # App icons and images
```

### Connection Flow

1. **QR Scan**: Scan QR code from Mac app setup
2. **Profile Parse**: Extract connection details from QR payload
3. **Credential Store**: Save SSH credentials to Keychain
4. **Connection Test**: Verify SSH connection works
5. **Session Attach**: Connect to tmux Claude Code session
6. **Conversation Sync**: Display current conversation state

### Session Management

- **tmux Integration**: Connects to existing Claude Code tmux session
- **Real-time Updates**: Streams conversation updates via SSH
- **Input Forwarding**: Sends user input to Claude Code session
- **State Preservation**: Maintains conversation state across app launches

## Development

### Requirements
- Xcode 15.0+
- iOS 17.0+ deployment target
- Swift 5.9+

### Building
```bash
cd ios-app
open VibeCode.xcodeproj
# Build and run in Xcode
```

### Testing
- Unit tests for core managers and models
- UI tests for main user flows
- Integration tests with mock SSH connections

### Dependencies
- **SwiftUI**: Modern UI framework
- **Network**: SSH client implementation
- **AVFoundation**: QR code scanning
- **Security**: Keychain integration

## User Experience

### First Launch
1. Welcome screen explaining the concept
2. QR code scanner for Mac app pairing
3. Automatic connection test and validation
4. Tutorial showing basic usage

### Daily Usage
1. Open app - automatic connection to Mac
2. See current Claude Code conversation
3. Continue typing to Claude naturally
4. Seamless experience as if on laptop

### Error Handling
- Connection failure recovery
- Network change adaptation
- Clear error messages and resolution steps
- Offline state handling

## App Store Considerations

### Privacy
- No data collection beyond necessary connection info
- Local-only credential storage
- Clear privacy policy about SSH connections

### Permissions
- Camera access for QR scanning
- Network access for SSH connections
- Keychain access for credential storage

### Screenshots and Metadata
- Demo showing laptop-to-iPhone continuity
- Clear value proposition in app description
- Screenshots showing setup and usage flow