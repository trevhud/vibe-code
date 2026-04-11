import Foundation
import SwiftUI
import Combine

enum AppPhase {
    case setup
    case sessionPicker
    case voice
}

@MainActor
class AppState: ObservableObject {
    @Published var phase: AppPhase = .setup
    @Published var connectionProfile: ConnectionProfile?
    @Published var discoveredSessions: [DiscoveredSession] = []
    @Published var navigationPath = NavigationPath()
    @Published var selectedSession: DiscoveredSession?

    let relayClient = RelayClient()
    let ttsProvider = AppleTTSProvider()
    let settingsManager = SettingsManager()

    /// ElevenLabs agent ID — set via Settings or environment.
    /// Create an agent at https://elevenlabs.io/app/conversational-ai
    /// with a custom LLM pointing to your relay server's /v1/chat/completions.
    var elevenLabsAgentId: String {
        settingsManager.elevenLabsAgentId ?? ""
    }

    /// Whether an ElevenLabs agent ID has been configured
    var hasAgentId: Bool {
        !elevenLabsAgentId.isEmpty
    }

    private(set) lazy var voiceProvider: ElevenLabsVoiceProvider = ElevenLabsVoiceProvider(
        agentIdProvider: { [weak self] in self?.elevenLabsAgentId ?? "" },
        fallbackTTS: ttsProvider
    )

    private(set) lazy var voiceSessionManager = VoiceSessionManager(
        relayClient: relayClient,
        voiceProvider: voiceProvider,
        fallbackTTS: ttsProvider
    )

    private var cancellables = Set<AnyCancellable>()

    init() {
        loadSavedProfile()
        subscribeToRelayMessages()
        observeNavigationPath()
        forwardNestedChanges()
    }

    /// Forward objectWillChange from nested ObservableObjects so SwiftUI re-renders.
    /// Must be synchronous (no receive(on:)) so the signal arrives before the change.
    private func forwardNestedChanges() {
        voiceSessionManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        relayClient.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Setup

    func setupConnection(with profile: ConnectionProfile) {
        self.connectionProfile = profile
        settingsManager.saveProfile(profile)
        settingsManager.storeRelayToken(profile.token)

        relayClient.connect(url: profile.relayUrl, token: profile.token)
        phase = .sessionPicker
    }

    func reconnect() {
        guard let profile = connectionProfile else { return }
        relayClient.connect(url: profile.relayUrl, token: profile.token)
    }

    func updateRelayUrl(_ newUrl: String) {
        guard let profile = connectionProfile else { return }
        let updated = ConnectionProfile(relayUrl: newUrl, token: profile.token, hostname: profile.hostname, created: profile.created)
        connectionProfile = updated
        settingsManager.saveProfile(updated)
        relayClient.connect(url: newUrl, token: profile.token)
    }

    func requestSessions() {
        relayClient.requestSessions()
    }

    func selectSession(_ session: DiscoveredSession) {
        selectedSession = session
        voiceSessionManager.attachToSession(session.id)
        navigationPath.append(session.id)
    }

    func reset() async {
        await voiceSessionManager.detach()
        relayClient.disconnect()
        connectionProfile = nil
        discoveredSessions = []
        settingsManager.clearProfile()
        phase = .setup
    }

    func goBackToSessionPicker() async {
        await voiceSessionManager.detach()
        selectedSession = nil
        navigationPath = NavigationPath()
        requestSessions()
    }

    // MARK: - Navigation

    private func observeNavigationPath() {
        $navigationPath
            .receive(on: DispatchQueue.main)
            .sink { [weak self] path in
                guard let self else { return }
                // User swiped back — detach from session
                if path.isEmpty && self.selectedSession != nil {
                    Task { await self.voiceSessionManager.detach() }
                    self.selectedSession = nil
                    self.requestSessions()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Private

    private func loadSavedProfile() {
        if let profile = settingsManager.loadProfile() {
            connectionProfile = profile
            relayClient.connect(url: profile.relayUrl, token: profile.token)
            phase = .sessionPicker
        }
    }

    private func subscribeToRelayMessages() {
        relayClient.messages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                guard let self else { return }
                switch message {
                case .sessionList(let sessions):
                    self.discoveredSessions = sessions

                case .authResult(let success, _):
                    if success && self.phase == .sessionPicker {
                        self.requestSessions()
                    }

                default:
                    break
                }
            }
            .store(in: &cancellables)

        // Auto-request sessions when connected
        relayClient.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                if state == .connected {
                    self?.requestSessions()
                }
            }
            .store(in: &cancellables)
    }
}
