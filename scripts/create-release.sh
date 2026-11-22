#!/bin/bash

# Vibe Code Release Script
# Usage: ./scripts/create-release.sh [version]
# Example: ./scripts/create-release.sh v1.0.0

set -e

VERSION=${1:-"v1.0.0"}
echo "🚀 Creating release for version: $VERSION"

# Ensure we're in the right directory
if [ ! -f "mac-app/Package.swift" ]; then
    echo "❌ Error: Please run this script from the vibe-code root directory"
    exit 1
fi

# Clean previous builds
echo "🧹 Cleaning previous builds..."
rm -rf mac-app/.build dist

# Create distribution directory
mkdir -p dist/releases

echo "🔨 Building for ARM64..."
cd mac-app
swift build -c release --arch arm64

echo "🔨 Building for x86_64..."
swift build -c release --arch x86_64

cd ..

echo "📦 Creating release packages..."

# Copy and package ARM64
cp mac-app/.build/arm64-apple-macosx/release/vibe-code dist/vibe-code
tar -czf "dist/releases/vibe-code-macos-arm64.tar.gz" -C dist vibe-code

# Copy and package x86_64
cp mac-app/.build/x86_64-apple-macosx/release/vibe-code dist/vibe-code
tar -czf "dist/releases/vibe-code-macos-x64.tar.gz" -C dist vibe-code

# Generate checksums
echo "🔐 Generating checksums..."
cd dist/releases
shasum -a 256 -- *.tar.gz > checksums.txt
cd ../..

# Extract SHA256 hashes for formula
ARM64_SHA=$(grep arm64 dist/releases/checksums.txt | cut -d' ' -f1)
X64_SHA=$(grep x64 dist/releases/checksums.txt | cut -d' ' -f1)

echo "📝 Updating Homebrew formula..."

# Update the formula with new version and hashes
cat > homebrew-setup/Formula/vibe-code.rb << EOF
class VibeCode < Formula
  desc "Seamlessly continue Claude Code conversations on your iPhone"
  homepage "https://github.com/trevhud/vibe-code"
  version "${VERSION#v}"

  if OS.mac?
    if Hardware::CPU.arm?
      url "https://github.com/trevhud/vibe-code/releases/download/${VERSION}/vibe-code-macos-arm64.tar.gz"
      sha256 "${ARM64_SHA}"
    else
      url "https://github.com/trevhud/vibe-code/releases/download/${VERSION}/vibe-code-macos-x64.tar.gz"
      sha256 "${X64_SHA}"
    end
  end

  # Tailscale is not a formula dependency: \`vibe-code setup\` uses whichever
  # tailscale is on PATH and installs one only when none is found.
  depends_on "tmux"

  def install
    bin.install "vibe-code"
  end

  def post_install
    puts "🎉 Vibe Code installed successfully!"
    puts ""
    puts "Next steps:"
    puts "1. Run 'vibe-code setup' to configure your system"
    puts "2. Download Vibe Code from the App Store on your iPhone"
    puts "3. Follow the setup guide: https://github.com/trevhud/vibe-code#setup"
  end

  test do
    assert_match "vibe-code", shell_output("#{bin}/vibe-code --version")
  end
end
EOF

echo "✅ Release packages created:"
ls -la dist/releases/

echo ""
echo "📋 Release Summary:"
echo "Version: $VERSION"
echo "ARM64 SHA256: $ARM64_SHA"
echo "x64 SHA256: $X64_SHA"
echo ""

echo "🚀 Next steps:"
echo "1. Test the build locally:"
echo "   brew install --build-from-source ./homebrew-setup/Formula/vibe-code.rb"
echo ""
echo "2. Create GitHub release:"
echo "   gh release create $VERSION dist/releases/* --title \"Vibe Code $VERSION\" --notes-file RELEASE_NOTES.md"
echo ""
echo "3. Copy formula to homebrew-vibe-code repository"
echo ""
echo "4. Users can then install with:"
echo "   brew tap trevhud/vibe-code"
echo "   brew install vibe-code"