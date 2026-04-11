import ArgumentParser
import Foundation

@main
struct VibeCode: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "vibe-code",
        abstract: "Seamlessly continue Claude Code conversations on your iPhone",
        version: "1.0.0",
        subcommands: [
            Setup.self,
            Status.self,
            Connect.self,
            Sessions.self,
            Restart.self,
            Doctor.self
        ],
        defaultSubcommand: Status.self
    )
}

// MARK: - Subcommands

extension VibeCode {
    struct Setup: AsyncParsableCommand {
        static var configuration = CommandConfiguration(
            abstract: "Set up Vibe Code for the first time"
        )
        
        func run() async throws {
            let setupManager = SetupManager()
            try await setupManager.runSetup()
        }
    }
    
    struct Status: AsyncParsableCommand {
        static var configuration = CommandConfiguration(
            abstract: "Show connection status and health"
        )
        
        func run() async throws {
            let healthMonitor = HealthMonitor()
            try await healthMonitor.showStatus()
        }
    }
    
    struct Connect: AsyncParsableCommand {
        static var configuration = CommandConfiguration(
            abstract: "Display QR code for iPhone pairing"
        )
        
        func run() async throws {
            let connectionManager = ConnectionManager()
            try await connectionManager.showQRCode()
        }
    }
    
    struct Sessions: AsyncParsableCommand {
        static var configuration = CommandConfiguration(
            abstract: "List all Claude Code sessions"
        )
        
        func run() async throws {
            let sessionManager = SessionManager()
            let sessions = await sessionManager.getAllClaudeSessions()
            
            if sessions.isEmpty {
                print("No Claude Code sessions found.")
                print("Start Claude in a project directory to create a session.")
                return
            }
            
            print("📺 Claude Code Sessions")
            print("======================")
            print()
            
            for session in sessions {
                let status = session.running ? "🟢 Active" : "🔴 Stopped"
                let clients = session.clientCount > 0 ? " (\(session.clientCount) connected)" : ""
                
                print("📁 \(session.folderName)")
                print("   Session: \(session.name)")
                print("   Status: \(status)\(clients)")
                if let workingDir = session.workingDirectory {
                    print("   Directory: \(workingDir)")
                }
                if let created = session.created {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .short
                    formatter.timeStyle = .short
                    print("   Created: \(formatter.string(from: created))")
                }
                print()
            }
            
            print("To connect from your iPhone:")
            print("1. cd to the project directory")
            print("2. Run 'vibe-code connect'")
            print("3. Scan the QR code")
        }
    }
    
    struct Restart: AsyncParsableCommand {
        static var configuration = CommandConfiguration(
            abstract: "Restart the Claude Code session"
        )
        
        func run() async throws {
            let sessionManager = SessionManager()
            try await sessionManager.restartSession()
        }
    }
    
    struct Doctor: AsyncParsableCommand {
        static var configuration = CommandConfiguration(
            abstract: "Run diagnostics and troubleshooting"
        )
        
        func run() async throws {
            let healthMonitor = HealthMonitor()
            try await healthMonitor.runDiagnostics()
        }
    }
}