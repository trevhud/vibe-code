import Foundation

class SetupManager {
    private let fileManager = FileManager.default
    private let process = ProcessRunner()
    
    func runSetup() async throws {
        print("🚀 Starting Vibe Code setup...")
        print()
        
        // Step 1: Check and install Tailscale
        try await setupTailscale()
        
        // Step 2: Configure SSH
        try await setupSSH()
        
        // Step 3: Setup tmux and session management
        try await setupTmux()
        
        // Step 4: Configure shell auto-attach
        try await setupShellIntegration()
        
        // Step 5: Generate connection profile
        try await generateConnectionProfile()
        
        print("✅ Setup complete!")
        print()
        print("Next steps:")
        print("1. Download Vibe Code from the App Store on your iPhone")
        print("2. Install Tailscale on your iPhone and sign in")
        print("3. Run 'vibe-code connect' to show the QR code")
        print("4. Scan the QR code with Vibe Code app")
        print()
    }
    
    private func setupTailscale() async throws {
        print("📡 Setting up Tailscale...")
        
        // Check if Tailscale is already installed
        let tailscaleInstalled = await process.runCommand("which", args: ["tailscale"]).success
        
        if !tailscaleInstalled {
            print("Installing Tailscale via Homebrew...")
            let installResult = await process.runCommand("brew", args: ["install", "tailscale"])
            
            if !installResult.success {
                print("❌ Failed to install Tailscale via Homebrew")
                print("Please install Tailscale manually: https://tailscale.com/download/mac")
                throw SetupError.tailscaleInstallationFailed
            }
        }
        
        // Check if Tailscale is authenticated
        let statusResult = await process.runCommand("tailscale", args: ["status"])
        
        if statusResult.output.contains("Logged out") {
            print("Please authenticate Tailscale...")
            print("Opening browser for authentication...")
            
            let authResult = await process.runCommand("tailscale", args: ["up"])
            if !authResult.success {
                print("❌ Failed to authenticate Tailscale")
                throw SetupError.tailscaleAuthenticationFailed
            }
            
            // Wait for authentication
            print("Waiting for authentication to complete...")
            try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        }
        
        // Get Tailscale IP
        let ipResult = await process.runCommand("tailscale", args: ["ip", "-4"])
        guard ipResult.success, !ipResult.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("❌ Failed to get Tailscale IP address")
            throw SetupError.tailscaleConfigurationFailed
        }
        
        let tailscaleIP = ipResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        print("✅ Tailscale configured with IP: \(tailscaleIP)")
    }
    
    private func setupSSH() async throws {
        print("🔐 Setting up SSH...")
        
        // Enable SSH on macOS
        let sshEnableResult = await process.runCommand("sudo", args: ["systemsetup", "-setremotelogin", "on"])
        if !sshEnableResult.success {
            print("❌ Failed to enable SSH. You may need to enable it manually in System Preferences.")
        } else {
            print("✅ SSH server enabled")
        }
        
        // Create SSH directory if it doesn't exist
        let sshDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        try fileManager.createDirectory(at: sshDir, withIntermediateDirectories: true)
        
        // Generate SSH key for Vibe Code if it doesn't exist
        let keyPath = sshDir.appendingPathComponent("vibe-code")
        let pubKeyPath = sshDir.appendingPathComponent("vibe-code.pub")
        
        if !fileManager.fileExists(atPath: keyPath.path) {
            print("Generating SSH key pair...")
            let keygenResult = await process.runCommand("ssh-keygen", args: [
                "-t", "ed25519",
                "-f", keyPath.path,
                "-N", "",
                "-C", "vibe-code-key"
            ])
            
            if !keygenResult.success {
                print("❌ Failed to generate SSH key")
                throw SetupError.sshKeyGenerationFailed
            }
        }
        
        // Add public key to authorized_keys
        let authorizedKeysPath = sshDir.appendingPathComponent("authorized_keys")
        let publicKey = try String(contentsOf: pubKeyPath)
        
        var authorizedKeys = ""
        if fileManager.fileExists(atPath: authorizedKeysPath.path) {
            authorizedKeys = try String(contentsOf: authorizedKeysPath)
        }
        
        if !authorizedKeys.contains("vibe-code-key") {
            authorizedKeys += "\n" + publicKey
            try authorizedKeys.write(to: authorizedKeysPath, atomically: true, encoding: .utf8)
        }
        
        // Set proper permissions
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: authorizedKeysPath.path)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyPath.path)
        try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: pubKeyPath.path)
        
        print("✅ SSH configured with Vibe Code key")
    }
    
    private func setupTmux() async throws {
        print("📺 Setting up tmux...")
        
        // Check if tmux is installed
        let tmuxInstalled = await process.runCommand("which", args: ["tmux"]).success
        
        if !tmuxInstalled {
            print("Installing tmux via Homebrew...")
            let installResult = await process.runCommand("brew", args: ["install", "tmux"])
            
            if !installResult.success {
                print("❌ Failed to install tmux")
                throw SetupError.tmuxInstallationFailed
            }
        }
        
        print("✅ tmux configured")
    }
    
    private func setupShellIntegration() async throws {
        print("🐚 Setting up shell integration...")
        
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let shellRcFiles = [".zshrc", ".bashrc", ".bash_profile"]
        
        let autoAttachScript = """
        
        # Vibe Code auto-attach configuration
        if [[ -z "$TMUX" && -n "$SSH_CONNECTION" ]]; then
            # Generate session name based on current directory
            FOLDER_NAME=$(basename "$PWD")
            SESSION_NAME="claude-${FOLDER_NAME}"
            
            tmux attach-session -t "$SESSION_NAME" 2>/dev/null || {
                tmux new-session -s "$SESSION_NAME" -d
                tmux send-keys -t "$SESSION_NAME" 'claude' Enter
                tmux attach-session -t "$SESSION_NAME"
            }
        fi
        """
        
        // Find the active shell config file
        var configFile: URL?
        for rcFile in shellRcFiles {
            let rcPath = homeDir.appendingPathComponent(rcFile)
            if fileManager.fileExists(atPath: rcPath.path) {
                configFile = rcPath
                break
            }
        }
        
        // Default to .zshrc if no config file found (zsh is default on macOS)
        if configFile == nil {
            configFile = homeDir.appendingPathComponent(".zshrc")
        }
        
        guard let configFile = configFile else {
            throw SetupError.shellConfigurationFailed
        }
        
        // Check if auto-attach is already configured
        var rcContent = ""
        if fileManager.fileExists(atPath: configFile.path) {
            rcContent = try String(contentsOf: configFile)
        }
        
        if !rcContent.contains("Vibe Code auto-attach") {
            rcContent += autoAttachScript
            try rcContent.write(to: configFile, atomically: true, encoding: .utf8)
            print("✅ Shell auto-attach configured in \(configFile.lastPathComponent)")
        } else {
            print("✅ Shell auto-attach already configured")
        }
    }
    
    private func generateConnectionProfile() async throws {
        print("🔗 Generating connection profile...")
        
        // Get Tailscale IP
        let ipResult = await process.runCommand("tailscale", args: ["ip", "-4"])
        guard ipResult.success else {
            throw SetupError.tailscaleConfigurationFailed
        }
        
        let tailscaleIP = ipResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = NSUserName()
        
        // Read the public key
        let sshDir = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        let pubKeyPath = sshDir.appendingPathComponent("vibe-code.pub")
        let publicKey = try String(contentsOf: pubKeyPath).trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Get current directory for session naming
        let currentDir = fileManager.currentDirectoryPath
        let folderName = URL(fileURLWithPath: currentDir).lastPathComponent
        let sessionName = "claude-\(folderName)"
        
        // Create connection profile
        let profile = ConnectionProfile(
            host: tailscaleIP,
            port: 22,
            username: username,
            publicKey: publicKey,
            sessionName: sessionName,
            created: Date()
        )
        
        // Save profile for QR code generation
        let profileData = try JSONEncoder().encode(profile)
        let vibeCodeDir = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".vibe-code")
        try fileManager.createDirectory(at: vibeCodeDir, withIntermediateDirectories: true)
        
        let profilePath = vibeCodeDir.appendingPathComponent("connection-profile.json")
        try profileData.write(to: profilePath)
        
        print("✅ Connection profile generated")
    }
}

// MARK: - Supporting Types

enum SetupError: Error, LocalizedError {
    case tailscaleInstallationFailed
    case tailscaleAuthenticationFailed
    case tailscaleConfigurationFailed
    case sshKeyGenerationFailed
    case tmuxInstallationFailed
    case shellConfigurationFailed
    
    var errorDescription: String? {
        switch self {
        case .tailscaleInstallationFailed:
            return "Failed to install Tailscale"
        case .tailscaleAuthenticationFailed:
            return "Failed to authenticate with Tailscale"
        case .tailscaleConfigurationFailed:
            return "Failed to configure Tailscale"
        case .sshKeyGenerationFailed:
            return "Failed to generate SSH key"
        case .tmuxInstallationFailed:
            return "Failed to install tmux"
        case .shellConfigurationFailed:
            return "Failed to configure shell integration"
        }
    }
}

struct ConnectionProfile: Codable {
    let host: String
    let port: Int
    let username: String
    let publicKey: String
    let sessionName: String
    let created: Date
}