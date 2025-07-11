# Vibe Code Architecture

## Overview
Vibe Code enables seamless continuation of Claude Code conversations from Mac to iPhone anywhere in the world, with per-project session management.

## Core Components

### Mac App (`vibe-code` CLI)
**Location**: `mac-app/`  
**Language**: Swift  
**Purpose**: Setup, session management, and connection coordination

#### Commands
- `vibe-code setup` - Complete system setup (Tailscale, SSH, tmux)
- `vibe-code connect` - Display QR code for current project session
- `vibe-code sessions` - List all active Claude Code sessions
- `vibe-code status` - Show health for current project
- `vibe-code restart` - Restart current project session
- `vibe-code doctor` - Run comprehensive diagnostics

#### Key Features
- **Automatic Tailscale setup** - Installs and configures Tailscale VPN
- **SSH server configuration** - Enables remote access with dedicated keys
- **Shell integration** - Auto-attach to project sessions via SSH
- **Per-folder sessions** - Creates `claude-{folder-name}` tmux sessions
- **QR code generation** - Includes connection details and available sessions

### iPhone App
**Location**: `ios-app/`  
**Language**: Swift/SwiftUI  
**Purpose**: Mobile interface for Claude Code conversations

#### Key Features
- **QR code scanning** - Camera-based setup with session detection
- **Session picker** - Choose from multiple available project sessions
- **Chat interface** - Mobile-optimized conversation view
- **Secure storage** - Credentials saved in iOS Keychain
- **Real-time status** - Connection health monitoring

#### App Flow
1. **Setup**: Scan QR code or manual configuration
2. **Session Selection**: Pick project if multiple sessions available
3. **Chat Interface**: Continue Claude Code conversations
4. **Settings**: Manage connections and troubleshoot

## Session Management

### Session Naming Convention
- **Format**: `claude-{folder-name}`
- **Examples**:
  - `~/Code/vibe-code` → `claude-vibe-code`
  - `~/Code/soundtrak` → `claude-soundtrak` 
  - `~/Code/my-project` → `claude-my-project`

### Session Lifecycle
1. **Creation**: When Claude starts in a project directory
2. **Auto-attach**: SSH connections automatically join correct session
3. **Persistence**: Sessions survive laptop sleep/wake
4. **Multiple clients**: Mac terminals + iPhone can connect simultaneously

### Multi-Project Workflow
```bash
# Terminal 1 - Working on Vibe Code
cd ~/Code/vibe-code
claude                    # Creates/joins claude-vibe-code session

# Terminal 2 - Working on Soundtrak  
cd ~/Code/soundtrak
claude                    # Creates/joins claude-soundtrak session

# iPhone - Choose which project to continue
vibe-code connect         # Shows QR with available sessions
```

## Security Architecture

### Network Security
- **Tailscale VPN**: All traffic encrypted via WireGuard protocol
- **Zero-trust networking**: Only authenticated devices can connect
- **No external servers**: Direct device-to-device communication

### Authentication
- **SSH key pairs**: Dedicated keys for Vibe Code (`~/.ssh/vibe-code`)
- **iOS Keychain**: Secure credential storage on iPhone
- **Auto-generated**: No manual key management required

### Data Privacy
- **Local-only**: No conversation data leaves your devices
- **No cloud storage**: All sessions stored locally in tmux
- **Minimal payload**: QR codes contain only connection metadata

## Technical Stack

### Mac App Dependencies
- **ArgumentParser**: Command-line interface
- **Swift Crypto**: Secure key generation
- **QRCodeGenerator**: Terminal QR code display

### iPhone App Dependencies
- **SwiftUI**: Modern iOS interface framework
- **AVFoundation**: Camera access for QR scanning
- **NIO/NIOSSH**: SSH client implementation
- **Security Framework**: Keychain access

### System Dependencies
- **Tailscale**: VPN networking (auto-installed)
- **tmux**: Terminal multiplexer (auto-installed)
- **SSH**: Remote shell access (system component)

## Development Status

### ✅ Completed
- Mac app with full session management
- iPhone app with QR scanning and session picker
- Per-folder session architecture
- Comprehensive documentation
- Security implementation
- Error handling and diagnostics

### 🚧 Next Steps
- SSH connection implementation in iPhone app
- tmux session streaming and interaction
- Conversation history synchronization
- End-to-end testing
- App Store preparation

## Usage Patterns

### Daily Workflow
1. Work on project in terminal with Claude
2. Leave home/office with laptop
3. Open Vibe Code on iPhone anywhere
4. Continue same conversation seamlessly
5. Switch between projects as needed

### Multi-Project Development
- Maintain separate Claude conversations per project
- Context-specific discussions and file references
- Easy switching between active projects
- Parallel development workflows

This architecture provides a robust foundation for seamless Claude Code mobility while maintaining security, performance, and user experience standards.