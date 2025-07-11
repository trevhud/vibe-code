# Homebrew Setup Guide

This guide walks through setting up Homebrew distribution for Vibe Code.

## Overview

Vibe Code uses a Homebrew tap for easy installation. Users will install with:

```bash
brew tap trevhud/vibe-code
brew install vibe-code
vibe-code setup
```

## Setup Process

### 1. Create the Homebrew Tap Repository

Create a new GitHub repository named `homebrew-vibe-code`:

```bash
# Create new repo on GitHub
gh repo create trevhud/homebrew-vibe-code --public

# Clone and set up
git clone https://github.com/trevhud/homebrew-vibe-code.git
cd homebrew-vibe-code

# Copy formula structure
cp -r ../vibe-code/homebrew-setup/* .
git add .
git commit -m "Initial Homebrew tap setup"
git push
```

### 2. Create Your First Release

#### Option A: Manual Release

```bash
# From vibe-code directory
./scripts/create-release.sh v1.0.0

# This creates:
# - dist/releases/vibe-code-macos-arm64.tar.gz
# - dist/releases/vibe-code-macos-x64.tar.gz
# - dist/releases/checksums.txt
# - Updated homebrew-setup/Formula/vibe-code.rb

# Create GitHub release
gh release create v1.0.0 dist/releases/* \
  --title "Vibe Code v1.0.0" \
  --notes "Initial release of Vibe Code"

# Update homebrew-vibe-code repo
cd ../homebrew-vibe-code
cp ../vibe-code/homebrew-setup/Formula/vibe-code.rb Formula/
git add Formula/vibe-code.rb
git commit -m "Update formula for v1.0.0"
git push
```

#### Option B: Automated Release (Recommended)

Just push a tag and GitHub Actions handles everything:

```bash
git tag v1.0.0
git push origin v1.0.0

# GitHub Actions will:
# 1. Build for both architectures
# 2. Create release packages
# 3. Create GitHub release
# 4. Update the formula
```

### 3. Test Local Installation

Before releasing, test the formula locally:

```bash
# Test build from source
brew install --build-from-source ./homebrew-setup/Formula/vibe-code.rb

# Test the installation
vibe-code --help
vibe-code setup --help

# Clean up test installation
brew uninstall vibe-code
```

### 4. User Installation Flow

Once published, users follow this simple flow:

```bash
# Add the tap
brew tap trevhud/vibe-code

# Install vibe-code
brew install vibe-code

# Set up the system
vibe-code setup

# Generate QR code for iPhone
vibe-code connect
```

## Updating Releases

### For Patch Releases (1.0.1, 1.0.2, etc.)

```bash
# Update version in mac-app if needed
# Create and push tag
git tag v1.0.1
git push origin v1.0.1

# GitHub Actions automatically handles the rest
```

### For Major/Minor Releases

1. Update documentation
2. Test thoroughly
3. Create release notes
4. Follow same tag process

## Formula Structure

The Homebrew formula (`Formula/vibe-code.rb`) includes:

- **Metadata**: Description, homepage, version
- **Architecture support**: ARM64 and x86_64 binaries
- **Dependencies**: Tailscale and tmux
- **Installation**: Simple binary install
- **Post-install message**: Helpful next steps
- **Test**: Version check verification

## Troubleshooting

### Common Issues

**Formula audit fails:**
```bash
brew audit --strict Formula/vibe-code.rb
```

**Installation test fails:**
```bash
brew install --build-from-source --verbose Formula/vibe-code.rb
```

**Wrong architecture downloaded:**
```bash
# Check architecture detection
ruby -e "puts Hardware::CPU.arm? ? 'ARM64' : 'x86_64'"
```

### Formula Validation

Before releasing, validate the formula:

```bash
# Check syntax
ruby -c Formula/vibe-code.rb

# Run Homebrew audit
brew audit Formula/vibe-code.rb

# Test installation
brew install --build-from-source Formula/vibe-code.rb
```

## Best Practices

1. **Always test locally first**
2. **Use semantic versioning** (1.0.0, 1.1.0, 2.0.0)
3. **Keep formula simple** - avoid complex installation logic
4. **Include helpful post-install messages**
5. **Validate SHA256 hashes** before publishing
6. **Test on both ARM64 and x86_64** if possible

## Security Considerations

- **Verify checksums** - Always validate SHA256 hashes
- **Use HTTPS URLs** - GitHub releases provide secure downloads
- **Code signing** - Consider signing binaries for additional security
- **Dependency verification** - Ensure Tailscale and tmux are from official sources

This setup provides a professional distribution method that integrates smoothly with macOS development workflows.