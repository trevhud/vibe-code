# Vibe Code Mac App

Swift command-line application that automates the setup and management of Claude Code session sharing.

## Overview

The Mac app handles all the complex setup required for seamless iPhone connectivity:
- Tailscale installation and configuration
- SSH server setup and key management
- tmux session management for persistent Claude Code sessions
- QR code generation for iPhone pairing
- Health monitoring and diagnostics

## Commands

```bash
# Initial setup - installs and configures everything
vibe-code setup

# Check connection status and health
vibe-code status

# Display QR code for iPhone pairing
vibe-code connect

# Restart Claude Code session
vibe-code restart

# Run diagnostics
vibe-code doctor

# Show help
vibe-code --help
```

## Architecture

### Core Components

1. **SetupManager**: Handles Tailscale installation and SSH configuration
2. **SessionManager**: Manages tmux sessions and Claude Code processes
3. **ConnectionManager**: Generates secure connection profiles and QR codes
4. **HealthMonitor**: Monitors system health and provides diagnostics

### Setup Process

1. **Tailscale Check**: Verify installation or guide through setup
2. **SSH Configuration**: Enable SSH server and create secure keys
3. **tmux Setup**: Configure persistent session management
4. **Shell Integration**: Add auto-attach configuration to shell
5. **Connection Profile**: Generate secure credentials for iPhone
6. **QR Code Display**: Show pairing QR code

### Connection Profile Format

The QR code contains a JSON payload with:
```json
{
  "host": "100.64.1.2",           // Tailscale IP
  "port": 22,                     // SSH port
  "username": "username",         // User account
  "key": "ssh-ed25519 AAAA...",  // SSH public key
  "session": "claude-code",       // tmux session name
  "created": "2024-01-01T00:00:00Z"
}
```

## Development

### Building
```bash
cd mac-app
swift build
```

### Testing
```bash
swift test
```

### Installation for Development
```bash
swift build -c release
cp .build/release/vibe-code /usr/local/bin/
```

### Homebrew Formula (Future)
The app will be distributed via Homebrew for easy installation.

## Dependencies

- **ArgumentParser**: Command-line interface
- **Crypto**: Secure key generation
- **QRCodeGenerator**: QR code creation for iPhone pairing

## Security Considerations

- SSH keys are generated specifically for Vibe Code
- Connection profiles include expiration timestamps
- All communication encrypted via Tailscale
- No credentials stored on external servers