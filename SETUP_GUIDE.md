# Vibe Code Setup Guide

## Overview
Vibe Code lets you seamlessly continue your Claude Code conversations from your laptop on your iPhone anywhere in the world. Setup takes just 2 minutes with our automated Mac app.

## Prerequisites
- iPhone running iOS 17 or later
- Mac with Claude Code installed
- Tailscale account (free tier works - we'll help you set this up)

## Step 1: Install Vibe Code Mac App

```bash
brew install vibe-code
```

## Step 2: Run Setup

```bash
vibe-code setup
```

The Mac app will automatically:
- Install Tailscale (if not already installed)
- Guide you through Tailscale authentication
- Configure SSH access
- Set up tmux for persistent Claude Code sessions
- Configure auto-resume for seamless connection
- Generate a secure connection profile

## Step 3: Connect Your iPhone

1. **Download Vibe Code** from the App Store
2. **Install Tailscale** on your iPhone from the App Store
3. **Sign in to Tailscale** with the same account you used on Mac
4. **Open Vibe Code** on iPhone
5. **Scan QR Code** shown by the Mac app setup
6. **Done!** You're now connected

## Step 4: Usage

### Starting a Session
1. **Navigate to your project** - `cd ~/Code/my-project`
2. **Start Claude Code** - `claude` (creates session `claude-my-project`)
3. **Open Vibe Code** on your iPhone (anywhere in the world)
4. **Choose your project** - pick from available sessions or scan QR
5. **Continue typing** to Claude as if you never switched devices

### Key Benefits
- **Works anywhere** - connect from any location with internet
- **Project-based sessions** - separate conversations per project folder
- **Session switching** - choose which project to work on from your phone
- **Always available** - your Mac can be sleeping, Claude Code stays active
- **Secure** - all traffic encrypted through Tailscale VPN

## Troubleshooting

### Quick Fixes
- **Connection failed**: Check Tailscale is running on both devices
- **No conversation showing**: Ensure Claude Code is running in the background on Mac
- **App won't connect**: Try restarting Tailscale on iPhone

### Advanced Troubleshooting
- **List all sessions**: Run `vibe-code sessions` to see all active project sessions
- **Reset connection**: Run `vibe-code setup` again on Mac and re-scan QR code
- **Check status**: Run `vibe-code status` on Mac to see connection health for current folder
- **Restart session**: Run `vibe-code restart` to restart the Claude Code session for current folder

## Security & Privacy
- **End-to-end encrypted** via Tailscale VPN
- **No data stored** on Vibe Code servers
- **Local authentication** - credentials stored securely on your devices
- **Zero-trust network** - only your authenticated devices can connect

## Support
Issues? Run `vibe-code doctor` on your Mac for automated diagnostics, or contact support through the iPhone app.