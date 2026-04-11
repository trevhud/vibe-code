import Foundation

class SessionManager {
    private let process = ProcessRunner()
    
    func restartSession() async throws {
        print("🔄 Restarting Claude Code session...")
        
        // Get current directory for session naming
        let currentDir = FileManager.default.currentDirectoryPath
        let folderName = URL(fileURLWithPath: currentDir).lastPathComponent
        let sessionName = "claude-\(folderName)"
        
        print("Session name: \(sessionName)")
        print("Working directory: \(currentDir)")
        
        // Kill existing session if it exists
        let killResult = await process.runCommand("tmux", args: ["kill-session", "-t", sessionName])
        if killResult.success {
            print("✅ Killed existing session")
        }
        
        // Create new session
        print("Creating new Claude Code session...")
        
        let createResult = await process.runCommand("tmux", args: [
            "new-session",
            "-s", sessionName,
            "-d",
            "-c", currentDir
        ])
        
        if !createResult.success {
            print("❌ Failed to create tmux session")
            throw SessionError.sessionCreationFailed
        }
        
        // Start Claude in the session
        let claudeResult = await process.runCommand("tmux", args: [
            "send-keys",
            "-t", sessionName,
            "claude",
            "Enter"
        ])
        
        if !claudeResult.success {
            print("❌ Failed to start Claude")
            throw SessionError.claudeStartFailed
        }
        
        // Wait a moment for Claude to start
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        print("✅ Claude Code session restarted")
        print("Session name: \(sessionName)")
        print("Working directory: \(currentDir)")
        print()
        print("You can attach locally with: tmux attach-session -t \(sessionName)")
    }
    
    func getSessionStatus() async -> SessionStatus {
        let currentDir = FileManager.default.currentDirectoryPath
        let folderName = URL(fileURLWithPath: currentDir).lastPathComponent
        let sessionName = "claude-\(folderName)"
        
        return await getSessionStatus(for: sessionName)
    }
    
    func getSessionStatus(for sessionName: String) async -> SessionStatus {
        // Check if session exists
        let listResult = await process.runCommand("tmux", args: ["list-sessions"])
        
        let sessionExists = listResult.success && listResult.output.contains(sessionName)
        
        if !sessionExists {
            return SessionStatus(
                name: sessionName,
                exists: false,
                running: false,
                clientCount: 0,
                created: nil,
                lastActivity: nil,
                workingDirectory: nil
            )
        }
        
        // Get session details
        let infoResult = await process.runCommand("tmux", args: [
            "display-message",
            "-t", sessionName,
            "-p",
            "#{session_created},#{session_last_attached},#{session_attached},#{pane_current_path}"
        ])
        
        if infoResult.success {
            let parts = infoResult.output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ",")
            if parts.count >= 4 {
                let created = Date(timeIntervalSince1970: TimeInterval(String(parts[0])) ?? 0)
                let lastActivity = Date(timeIntervalSince1970: TimeInterval(String(parts[1])) ?? 0)
                let clientCount = Int(String(parts[2])) ?? 0
                let workingDirectory = String(parts[3])
                
                return SessionStatus(
                    name: sessionName,
                    exists: true,
                    running: true,
                    clientCount: clientCount,
                    created: created,
                    lastActivity: lastActivity,
                    workingDirectory: workingDirectory
                )
            }
        }
        
        return SessionStatus(
            name: sessionName,
            exists: true,
            running: false,
            clientCount: 0,
            created: nil,
            lastActivity: nil,
            workingDirectory: nil
        )
    }
    
    func getAllClaudeSessions() async -> [SessionStatus] {
        let listResult = await process.runCommand("tmux", args: ["list-sessions", "-F", "#{session_name}"])
        
        guard listResult.success else {
            return []
        }
        
        let sessionNames = listResult.output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("claude-") }
        
        var sessions: [SessionStatus] = []
        
        for sessionName in sessionNames {
            let status = await getSessionStatus(for: sessionName)
            sessions.append(status)
        }
        
        return sessions
    }
    
    func ensureSessionExists() async throws {
        let status = await getSessionStatus()
        
        if !status.exists {
            print("Creating Claude Code session...")
            try await restartSession()
        } else {
            print("✅ Claude Code session already exists")
        }
    }
}

// MARK: - Supporting Types

enum SessionError: Error, LocalizedError {
    case sessionCreationFailed
    case claudeStartFailed
    case tmuxNotFound
    
    var errorDescription: String? {
        switch self {
        case .sessionCreationFailed:
            return "Failed to create tmux session"
        case .claudeStartFailed:
            return "Failed to start Claude"
        case .tmuxNotFound:
            return "tmux is not installed"
        }
    }
}

struct SessionStatus {
    let name: String
    let exists: Bool
    let running: Bool
    let clientCount: Int
    let created: Date?
    let lastActivity: Date?
    let workingDirectory: String?
    
    var folderName: String {
        if name.hasPrefix("claude-") {
            return String(name.dropFirst(7)) // Remove "claude-" prefix
        }
        return name
    }
}