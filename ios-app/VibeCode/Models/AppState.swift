import Foundation
import SwiftUI

@MainActor
class AppState: ObservableObject {
    @Published var isSetupComplete: Bool = false
    @Published var connectionProfile: ConnectionProfile?
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var messages: [Message] = []
    @Published var isConnecting: Bool = false
    @Published var showingPasswordInput: Bool = false
    
    private let settingsManager = SettingsManager()
    private let connectionManager = ConnectionManager()
    private let conversationParser = ConversationParser()
    
    init() {
        loadSavedProfile()
        setupDelegates()
    }
    
    private func setupDelegates() {
        connectionManager.delegate = self
        conversationParser.delegate = self
    }
    
    func setupConnection(with profile: ConnectionProfile) {
        self.connectionProfile = profile
        self.isSetupComplete = true
        
        // Save profile for future use
        settingsManager.saveProfile(profile)
        
        // Start connection
        connectToSession()
    }
    
    func connectToSession() {
        guard let profile = connectionProfile else { return }
        
        // Check if we have stored password
        let storedPassword = settingsManager.retrievePassword(for: profile.username)
        
        if storedPassword == nil || storedPassword!.isEmpty {
            // Need to get password from user
            showingPasswordInput = true
            return
        }
        
        performConnection()
    }
    
    func connectWithPassword(_ password: String) {
        performConnection()
    }
    
    private func performConnection() {
        guard let profile = connectionProfile else { return }
        
        isConnecting = true
        connectionStatus = .connecting
        showingPasswordInput = false
        
        Task {
            do {
                try await connectionManager.connect(to: profile)
                await MainActor.run {
                    connectionStatus = .connected
                    isConnecting = false
                    loadConversationHistory()
                }
            } catch {
                await MainActor.run {
                    connectionStatus = .failed(error.localizedDescription)
                    isConnecting = false
                }
            }
        }
    }
    
    func sendMessage(_ text: String) {
        let message = Message(
            id: UUID(),
            content: text,
            sender: .user,
            timestamp: Date()
        )
        
        messages.append(message)
        
        Task {
            do {
                try await connectionManager.sendInput(text)
            } catch {
                await MainActor.run {
                    connectionStatus = .failed("Failed to send message: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func reset() {
        isSetupComplete = false
        connectionProfile = nil
        connectionStatus = .disconnected
        messages = []
        settingsManager.clearProfile()
        connectionManager.disconnect()
    }
    
    private func loadSavedProfile() {
        if let savedProfile = settingsManager.loadProfile() {
            connectionProfile = savedProfile
            isSetupComplete = true
        }
    }
    
    private func loadConversationHistory() {
        // Clear existing messages and reset parser
        messages.removeAll()
        conversationParser.reset()
        
        // Add connection message
        let welcomeMessage = Message(
            id: UUID(),
            content: "Connected to session: \(connectionProfile?.sessionName ?? "unknown")",
            sender: .system,
            timestamp: Date()
        )
        messages.append(welcomeMessage)
    }
}

// MARK: - ConnectionManagerDelegate

extension AppState: ConnectionManagerDelegate {
    func connectionManager(_ manager: ConnectionManager, receivedOutput output: String) {
        // Process output through conversation parser
        conversationParser.processOutput(output)
    }
}

// MARK: - ConversationParserDelegate

extension AppState: ConversationParserDelegate {
    func conversationParser(_ parser: ConversationParser, didParseMessage message: Message) {
        // Add parsed message to conversation
        messages.append(message)
    }
}

enum ConnectionStatus {
    case disconnected
    case connecting
    case connected
    case failed(String)
    
    var description: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        case .failed(let error):
            return "Failed: \(error)"
        }
    }
    
    var color: Color {
        switch self {
        case .disconnected:
            return .gray
        case .connecting:
            return .orange
        case .connected:
            return .green
        case .failed:
            return .red
        }
    }
}