import Foundation
import QRCodeGenerator

class ConnectionManager {
    private let fileManager = FileManager.default
    
    func showQRCode() async throws {
        print("📱 Generating QR code for iPhone pairing...")
        print()
        
        // Load connection profile
        let profile = try loadConnectionProfile()
        
        // Generate QR code
        let qrCode = try await generateQRCode(for: profile)
        
        // Display QR code in terminal
        displayQRCode(qrCode)
        
        print()
        print("📋 Connection Details:")
        print("Host: \(profile.host)")
        print("Username: \(profile.username)")
        print("Session: \(profile.sessionName)")
        print("Created: \(DateFormatter.localizedString(from: profile.created, dateStyle: .short, timeStyle: .short))")
        print()
        print("Instructions:")
        print("1. Open Vibe Code app on your iPhone")
        print("2. Tap 'Scan QR Code'")
        print("3. Point camera at the QR code above")
        print("4. Start chatting with Claude!")
        print()
    }
    
    private func loadConnectionProfile() throws -> ConnectionProfile {
        let vibeCodeDir = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".vibe-code")
        let profilePath = vibeCodeDir.appendingPathComponent("connection-profile.json")
        
        guard fileManager.fileExists(atPath: profilePath.path) else {
            print("❌ No connection profile found. Run 'vibe-code setup' first.")
            throw ConnectionError.profileNotFound
        }
        
        let profileData = try Data(contentsOf: profilePath)
        return try JSONDecoder().decode(ConnectionProfile.self, from: profileData)
    }
    
    private func generateQRCode(for profile: ConnectionProfile) async throws -> QRCode {
        // Get all available Claude sessions
        let sessionManager = SessionManager()
        let sessions = await sessionManager.getAllClaudeSessions()
        let sessionNames = sessions.map { $0.name }
        
        // Create connection payload
        let payload = ConnectionPayload(
            host: profile.host,
            port: profile.port,
            username: profile.username,
            sessionName: profile.sessionName,
            created: profile.created,
            availableSessions: sessionNames.isEmpty ? nil : sessionNames
        )
        
        let jsonData = try JSONEncoder().encode(payload)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        
        // Generate QR code
        return try QRCode.encode(text: jsonString, ecl: .medium)
    }
    
    private func displayQRCode(_ qrCode: QRCode) {
        print("Scan this QR code with your iPhone:")
        print()
        
        // Convert QR code to ASCII art for terminal display
        let size = qrCode.size
        
        // Add border
        let border = String(repeating: "██", count: size + 4)
        print(border)
        
        for y in 0..<size {
            var line = "██"
            for x in 0..<size {
                let module = qrCode.getModule(x: x, y: y)
                line += module ? "██" : "  "
            }
            line += "██"
            print(line)
        }
        
        print(border)
    }
}

// MARK: - Supporting Types

enum ConnectionError: Error, LocalizedError {
    case profileNotFound
    case qrGenerationFailed
    
    var errorDescription: String? {
        switch self {
        case .profileNotFound:
            return "Connection profile not found"
        case .qrGenerationFailed:
            return "Failed to generate QR code"
        }
    }
}

struct ConnectionPayload: Codable {
    let host: String
    let port: Int
    let username: String
    let sessionName: String
    let created: Date
    let availableSessions: [String]? // List of all available Claude sessions
    
    // Note: We don't include the actual SSH key in the QR code for security
    // The iPhone app will need to authenticate via password or we'll need
    // a secure key exchange mechanism
}