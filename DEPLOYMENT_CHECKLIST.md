# Vibe Code Deployment Checklist

## 🎯 **Ready to Deploy!**

Your Vibe Code Homebrew tap is ready. Here's what you need to do to go live:

## 1. Create the Homebrew Tap Repository

```bash
# Create the tap repository on GitHub
gh repo create trevhud/homebrew-vibe-code --public

# Clone and set up
git clone https://github.com/trevhud/homebrew-vibe-code.git
cd homebrew-vibe-code

# Copy the Homebrew setup
cp -r ../vibe-code/homebrew-setup/* .

# Initial commit
git add .
git commit -m "Initial Homebrew tap for Vibe Code"
git push
```

## 2. Create Your First Release

### Option A: Automated (Recommended)
```bash
# From vibe-code directory
git add .
git commit -m "Prepare for v1.0.0 release"
git tag v1.0.0
git push origin main
git push origin v1.0.0

# GitHub Actions will automatically:
# ✅ Build for ARM64 and x86_64
# ✅ Create release packages
# ✅ Create GitHub release
# ✅ Update Homebrew formula
```

### Option B: Manual
```bash
# Create release packages
./scripts/create-release.sh v1.0.0

# Create GitHub release
gh release create v1.0.0 dist/releases/* \
  --title "Vibe Code v1.0.0" \
  --notes "🎉 Initial release of Vibe Code - Continue Claude Code conversations on your iPhone!"

# Update tap repository
cd ../homebrew-vibe-code
cp ../vibe-code/homebrew-setup/Formula/vibe-code.rb Formula/
git add Formula/vibe-code.rb
git commit -m "Release v1.0.0"
git push
```

## 3. Test the Installation

```bash
# Test tap installation
brew tap trevhud/vibe-code

# Test installation
brew install vibe-code

# Test functionality
vibe-code --help
vibe-code setup --help

# Clean up test
brew uninstall vibe-code
brew untap trevhud/vibe-code
```

## 4. User Installation Flow

Once live, users will install with:

```bash
brew tap trevhud/vibe-code
brew install vibe-code
vibe-code setup
```

## 5. iPhone App Submission

For the iPhone app:
1. Build in Xcode with proper signing
2. Submit to App Store Connect
3. Pass App Store review
4. Coordinate release with Homebrew tap

## 6. Documentation Updates

Update your main README.md with:

```markdown
## Installation

### Mac Setup
```bash
brew tap trevhud/vibe-code
brew install vibe-code
vibe-code setup
```

### iPhone Setup
1. Download Vibe Code from the App Store
2. Install Tailscale on iPhone
3. Run `vibe-code connect` on Mac
4. Scan QR code with iPhone app
```

## Current Status

### ✅ **Completed**
- Mac CLI app with full functionality
- iPhone app with complete SSH integration
- GitHub Actions for automated releases
- Release automation scripts
- Homebrew formula
- Documentation

### 🚀 **Ready to Deploy**
- Release script tested and working
- Formula generates correctly
- Both ARM64 and x86_64 builds successful
- SHA256 checksums validated

### 📱 **Next Steps**
1. Create `homebrew-vibe-code` repository
2. Push first release tag
3. Test tap installation
4. Submit iPhone app to App Store

## Release Command Summary

```bash
# One-command release:
git tag v1.0.0 && git push origin v1.0.0

# Manual release:
./scripts/create-release.sh v1.0.0
```

You're ready to make Vibe Code available to the world! 🚀