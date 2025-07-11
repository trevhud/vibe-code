import Foundation

class HealthMonitor {
    private let process = ProcessRunner()
    private let sessionManager = SessionManager()
    
    func showStatus() async throws {
        print("📊 Vibe Code Status")
        print("===================")
        print()
        
        // Check Tailscale status
        await checkTailscaleStatus()
        print()
        
        // Check SSH status
        await checkSSHStatus()
        print()
        
        // Check tmux session status
        await checkSessionStatus()
        print()
        
        // Check connection profile
        await checkConnectionProfile()
        print()
        
        print("Run 'vibe-code doctor' for detailed diagnostics")
    }
    
    func runDiagnostics() async throws {
        print("🔍 Running Vibe Code Diagnostics")
        print("=================================")
        print()
        
        var issues: [String] = []
        
        // Comprehensive checks
        issues.append(contentsOf: await diagnoseTailscale())
        issues.append(contentsOf: await diagnoseSSH())
        issues.append(contentsOf: await diagnoseTmux())
        issues.append(contentsOf: await diagnoseSession())
        issues.append(contentsOf: await diagnoseNetworking())
        
        print()
        
        if issues.isEmpty {
            print("✅ All systems healthy!")
            print()
            print("Your Vibe Code setup is working correctly.")
            print("You can connect from your iPhone using 'vibe-code connect'")
        } else {
            print("⚠️  Issues Found:")
            print()
            for (index, issue) in issues.enumerated() {
                print("\(index + 1). \(issue)")
            }
            print()
            print("💡 Suggested fixes:")
            print("- Run 'vibe-code setup' to reconfigure")
            print("- Check that Tailscale is running on both devices")
            print("- Ensure your iPhone has Tailscale installed and authenticated")
        }
    }
    
    private func checkTailscaleStatus() async {
        print("🌐 Tailscale:")
        
        let statusResult = await process.runCommand("tailscale", args: ["status", "--json"])
        
        if !statusResult.success {
            print("   ❌ Not installed or not running")
            return
        }
        
        // Parse Tailscale status
        if let data = statusResult.output.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            
            let backendState = json["BackendState"] as? String ?? "unknown"
            
            switch backendState {
            case "Running":
                if let self = json["Self"] as? [String: Any],
                   let tailscaleIP = self["TailscaleIPs"] as? [String],
                   let firstIP = tailscaleIP.first {
                    print("   ✅ Connected (\(firstIP))")
                } else {
                    print("   ✅ Connected (IP unknown)")
                }
            case "Stopped":
                print("   ⚠️  Stopped - run 'tailscale up'")
            case "NeedsLogin":
                print("   ⚠️  Needs authentication - run 'tailscale up'")
            default:
                print("   ⚠️  Status: \(backendState)")
            }
        } else {
            print("   ⚠️  Status unknown")
        }
    }
    
    private func checkSSHStatus() async {
        print("🔐 SSH:")
        
        // Check if SSH is enabled
        let sshResult = await process.runCommand("systemsetup", args: ["-getremotelogin"])
        
        if sshResult.output.contains("On") {
            print("   ✅ SSH server enabled")
        } else {
            print("   ❌ SSH server disabled")
        }
        
        // Check SSH key
        let sshDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        let keyPath = sshDir.appendingPathComponent("vibe-code")
        
        if FileManager.default.fileExists(atPath: keyPath.path) {
            print("   ✅ Vibe Code SSH key exists")
        } else {
            print("   ❌ Vibe Code SSH key missing")
        }
    }
    
    private func checkSessionStatus() async {
        print("📺 tmux Session:")
        
        let status = await sessionManager.getSessionStatus()
        
        if status.exists {
            print("   ✅ Session '\(status.name)' exists")
            print("   📁 Project: \(status.folderName)")
            if status.clientCount > 0 {
                print("   📱 \(status.clientCount) client(s) connected")
            }
            if let workingDir = status.workingDirectory {
                print("   📂 Directory: \(workingDir)")
            }
            if let created = status.created {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short
                print("   📅 Created: \(formatter.string(from: created))")
            }
        } else {
            print("   ❌ Session '\(status.name)' not found")
            print("   💡 Run 'claude' in this directory to create it")
        }
    }
    
    private func checkConnectionProfile() async {
        print("🔗 Connection Profile:")
        
        let vibeCodeDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".vibe-code")
        let profilePath = vibeCodeDir.appendingPathComponent("connection-profile.json")
        
        if FileManager.default.fileExists(atPath: profilePath.path) {
            do {
                let profileData = try Data(contentsOf: profilePath)
                let profile = try JSONDecoder().decode(ConnectionProfile.self, from: profileData)
                print("   ✅ Profile exists")
                print("   🌐 Host: \(profile.host)")
                print("   👤 User: \(profile.username)")
            } catch {
                print("   ⚠️  Profile exists but corrupted")
            }
        } else {
            print("   ❌ Profile not found")
        }
    }
    
    // MARK: - Diagnostic Methods
    
    private func diagnoseTailscale() async -> [String] {
        var issues: [String] = []
        
        let whichResult = await process.runCommand("which", args: ["tailscale"])
        if !whichResult.success {
            issues.append("Tailscale is not installed")
            return issues
        }
        
        let statusResult = await process.runCommand("tailscale", args: ["status"])
        if !statusResult.success {
            issues.append("Tailscale is not running")
        } else if statusResult.output.contains("Logged out") {
            issues.append("Tailscale is not authenticated")
        }
        
        return issues
    }
    
    private func diagnoseSSH() async -> [String] {
        var issues: [String] = []
        
        let sshResult = await process.runCommand("systemsetup", args: ["-getremotelogin"])
        if !sshResult.output.contains("On") {
            issues.append("SSH server is disabled")
        }
        
        let sshDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        let keyPath = sshDir.appendingPathComponent("vibe-code")
        
        if !FileManager.default.fileExists(atPath: keyPath.path) {
            issues.append("SSH key for Vibe Code is missing")
        }
        
        return issues
    }
    
    private func diagnoseTmux() async -> [String] {
        var issues: [String] = []
        
        let whichResult = await process.runCommand("which", args: ["tmux"])
        if !whichResult.success {
            issues.append("tmux is not installed")
        }
        
        return issues
    }
    
    private func diagnoseSession() async -> [String] {
        var issues: [String] = []
        
        let status = await sessionManager.getSessionStatus()
        if !status.exists {
            issues.append("Claude Code tmux session does not exist")
        }
        
        return issues
    }
    
    private func diagnoseNetworking() async -> [String] {
        var issues: [String] = []
        
        // Test if we can reach ourselves via Tailscale
        let ipResult = await process.runCommand("tailscale", args: ["ip", "-4"])
        if ipResult.success {
            let ip = ipResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let pingResult = await process.runCommand("ping", args: ["-c", "1", "-W", "5000", ip])
            
            if !pingResult.success {
                issues.append("Cannot reach Tailscale IP via ping")
            }
        }
        
        return issues
    }
}