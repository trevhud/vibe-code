import Foundation
import Combine
import OSLog

@MainActor
class VoiceSessionManager: ObservableObject {
    @Published var voiceState: VoiceProviderState = .idle
    @Published var eventLog: [AgentEvent] = []
    @Published var currentSessionId: String?
    @Published var transcript: String = ""

    private let relayClient: RelayClient
    private let voiceProvider: any VoiceProvider
    private let fallbackTTS: AppleTTSProvider
    private var cancellables = Set<AnyCancellable>()
    private var isDetaching = false
    private var pendingContextUpdate: String?

    init(relayClient: RelayClient, voiceProvider: any VoiceProvider, fallbackTTS: AppleTTSProvider) {
        self.relayClient = relayClient
        self.voiceProvider = voiceProvider
        self.fallbackTTS = fallbackTTS

        subscribeToRelayEvents()
        observeVoiceProvider()
    }

    // MARK: - Conversation Control

    func startConversation() async throws {
        guard let sessionId = currentSessionId else { return }
        try await voiceProvider.startConversation(sessionId: sessionId)
    }

    func endConversation() async {
        await voiceProvider.endConversation()
    }

    func interrupt() {
        voiceProvider.interrupt()
    }

    // MARK: - Session Management

    func attachToSession(_ sessionId: String) {
        currentSessionId = sessionId
        eventLog = []
        relayClient.attach(sessionId: sessionId)
    }

    func detach() async {
        guard !isDetaching else { return }
        isDetaching = true
        defer { isDetaching = false }

        await voiceProvider.endConversation()
        relayClient.detach()
        currentSessionId = nil
        eventLog = []
    }

    // MARK: - Voice Provider Observation

    private func observeVoiceProvider() {
        voiceProvider.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                let wasSpeaking = self.voiceState == .speaking
                self.voiceState = state

                // Flush queued context update now that agent finished speaking
                if wasSpeaking && state != .speaking, let context = self.pendingContextUpdate {
                    self.pendingContextUpdate = nil
                    Task {
                        await self.voiceProvider.sendContextUpdate(context)
                    }
                }
            }
            .store(in: &cancellables)

        voiceProvider.transcriptPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.transcript = text
            }
            .store(in: &cancellables)

        voiceProvider.onUserTranscript = { [weak self] text in
            guard let self else { return }
            // User finished speaking — transcript was sent via the custom LLM webhook.
            // Use .queue priority so it stands out with an orange dot.
            let event = AgentEvent(
                priority: .queue,
                category: .progress,
                summary: "You: \(text)",
                timestamp: Date(),
                sessionId: self.currentSessionId ?? ""
            )
            self.eventLog.insert(event, at: 0)
        }

        voiceProvider.onError = { [weak self] error in
            self?.addSystemEvent(error.userMessage)
        }
    }

    // MARK: - Relay Event Handling

    private func subscribeToRelayEvents() {
        relayClient.messages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.handleDownstreamMessage(message)
            }
            .store(in: &cancellables)
    }

    private func handleDownstreamMessage(_ message: DownstreamMessage) {
        if case .agentEvent(_, _, _, let summary, _) = message {
            Logger.relay.debug("[EventStream] received: \(summary)")
        }
        switch message {
        case .agentEvent(let sessionId, let priority, let category, let summary, let timestamp):
            let event = AgentEvent(
                priority: priority,
                category: category,
                summary: summary,
                timestamp: ISO8601DateFormatter().date(from: timestamp) ?? Date(),
                sessionId: sessionId
            )
            eventLog.insert(event, at: 0)

            // Keep log manageable
            if eventLog.count > 100 {
                eventLog = Array(eventLog.prefix(100))
            }

            // Responses are spoken by ElevenLabs' built-in LLM via server tools.
            // No need to inject spoken responses here.

        case .sessionHistory(_, let events):
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let fallbackFormatter = ISO8601DateFormatter()
            fallbackFormatter.formatOptions = [.withInternetDateTime]

            let parsed: [AgentEvent] = events.map { e in
                let date = isoFormatter.date(from: e.timestamp)
                    ?? fallbackFormatter.date(from: e.timestamp)
                    ?? Date()
                return AgentEvent(
                    priority: e.priority,
                    category: e.category,
                    summary: e.summary,
                    timestamp: date,
                    sessionId: currentSessionId ?? ""
                )
            }
            // History comes oldest-first; display newest-first
            eventLog = parsed.reversed()

        case .inputAck(_, let success, let error):
            if !success {
                addSystemEvent("Failed to send: \(error ?? "unknown error")")
            }

        case .contextUpdate(_, let context):
            // Don't interrupt agent speech — queue and deliver after speaking ends
            if voiceState == .speaking {
                pendingContextUpdate = context
            } else {
                Task {
                    await voiceProvider.sendContextUpdate(context)
                }
            }

        case .sessionState(_, let state):
            if state == .disconnected {
                addSystemEvent("Session disconnected")
            }

        default:
            break
        }
    }

    private func addSystemEvent(_ message: String) {
        let event = AgentEvent(
            priority: .silent,
            category: .progress,
            summary: message,
            timestamp: Date(),
            sessionId: currentSessionId ?? ""
        )
        eventLog.insert(event, at: 0)
    }
}
