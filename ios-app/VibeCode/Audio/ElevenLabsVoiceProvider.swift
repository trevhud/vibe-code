import Foundation
import Combine
import ElevenLabs
import AVFoundation
import OSLog

@MainActor
final class ElevenLabsVoiceProvider: ObservableObject, VoiceProvider {

    // MARK: - Published State

    @Published private(set) var state: VoiceProviderState = .idle
    @Published private(set) var transcript: String = ""

    var statePublisher: AnyPublisher<VoiceProviderState, Never> {
        $state.eraseToAnyPublisher()
    }

    var transcriptPublisher: AnyPublisher<String, Never> {
        $transcript.eraseToAnyPublisher()
    }

    var isConnected: Bool {
        guard let conversation else { return false }
        return conversation.state.isActive
    }

    var onUserTranscript: ((String) -> Void)?
    var onError: ((VoiceProviderError) -> Void)?

    // MARK: - Private

    private let agentIdProvider: () -> String
    private let fallbackTTS: AppleTTSProvider
    private var conversation: Conversation?
    private var cancellables = Set<AnyCancellable>()
    private var currentSessionId: String?

    // MARK: - Init

    /// - Parameters:
    ///   - agentIdProvider: Closure that returns the current ElevenLabs agent ID (evaluated at conversation start)
    ///   - fallbackTTS: Apple TTS used for injecting async event speech
    init(agentIdProvider: @escaping () -> String, fallbackTTS: AppleTTSProvider) {
        self.agentIdProvider = agentIdProvider
        self.fallbackTTS = fallbackTTS
    }

    // MARK: - VoiceProvider

    func startConversation(sessionId: String) async throws {
        // End any existing conversation
        await endConversation()

        let agentId = agentIdProvider()
        guard !agentId.isEmpty else {
            onError?(.notConfigured("ElevenLabs agent ID not configured. Go to Settings."))
            return
        }

        currentSessionId = sessionId
        state = .connecting(.unknown)

        var config = ConversationConfig()
        config.dynamicVariables = ["sessionId": sessionId]

        // Force AEC (echo cancellation) on to prevent agent audio from being
        // picked up by the mic and triggering false user turns.
        config.audioConfiguration = AudioPipelineConfiguration(
            microphoneMuteMode: .inputMixer,
            recordingAlwaysPrepared: true,
            voiceProcessingBypassed: false,
            voiceProcessingAGCEnabled: true
        )

        // Log VAD scores during agent speech to diagnose echo-triggered false positives
        config.onVadScore = { [weak self] score in
            Task { @MainActor in
                guard let self, self.state == .speaking else { return }
                Logger.voice.debug("[VAD] score during agent speech: \(score)")
            }
        }

        config.onStartupStateChange = { [weak self] startupState in
            Task { @MainActor in
                guard let self else { return }
                switch startupState {
                case .resolvingToken:
                    self.state = .connecting(.resolvingToken)
                case .connectingRoom:
                    self.state = .connecting(.connectingRoom)
                case .waitingForAgent:
                    self.state = .connecting(.waitingForAgent)
                case .sendingConversationInit:
                    self.state = .connecting(.sendingInit)
                case .failed(let failure, _):
                    self.onError?(Self.mapStartupFailure(failure))
                    self.state = .idle
                    self.conversation = nil
                default:
                    break
                }
            }
        }

        config.onError = { [weak self] error in
            Task { @MainActor in
                self?.onError?(.unknown("\(error)"))
                self?.state = .idle
            }
        }
        config.onUserTranscript = { [weak self] text, _ in
            Task { @MainActor in
                guard let self else { return }
                self.transcript = text
                self.onUserTranscript?(text)
            }
        }

        let conv = try await ElevenLabs.startConversation(
            agentId: agentId,
            config: config,
            onAgentReady: { [weak self] in
                Task { @MainActor in
                    self?.state = .listening
                    // Route audio to loudspeaker after SDK configures the session
                    self?.configureAudioSession()
                }
            },
            onDisconnect: { [weak self] _ in
                Task { @MainActor in
                    self?.state = .idle
                    self?.conversation = nil
                }
            }
        )

        self.conversation = conv
        observeConversation(conv)

        // Route audio to loudspeaker immediately (LiveKit defaults to earpiece)
        configureAudioSession()
    }

    func endConversation() async {
        let conv = conversation
        conversation = nil        // Gate observation handlers
        currentSessionId = nil

        if let conv {
            await conv.endConversation()
        }

        cancellables.removeAll()
        state = .idle
        transcript = ""
    }

    func interrupt() {
        guard let conversation else { return }
        Task {
            do {
                try await conversation.interruptAgent()
            } catch {
                onError?(.unknown("Failed to interrupt: \(error.localizedDescription)"))
            }
        }
    }

    func sendContextUpdate(_ context: String) async {
        guard let conversation, conversation.state.isActive else { return }
        // Never send messages while the agent is speaking — this interrupts TTS
        guard state != .speaking else {
            Logger.voice.info("[ContextUpdate] skipped — agent is speaking")
            return
        }
        do {
            // Send as a [SYSTEM:] message to trigger the agent to speak proactively.
            // The agent's system prompt knows to relay these naturally.
            try await conversation.sendMessage("[SYSTEM: \(context)]")
        } catch {
            onError?(.unknown("Context update failed: \(error.localizedDescription)"))
        }
    }

    func injectSpokenResponse(_ text: String) async {
        guard let conversation, conversation.state.isActive else { return }

        do {
            try await conversation.setMuted(true)
        } catch {
            onError?(.microphoneFailure("Mute failed, skipping TTS"))
            return  // Skip TTS rather than playing with mic open
        }

        await fallbackTTS.speak(text)

        if let conversation = self.conversation, conversation.state.isActive {
            do {
                try await conversation.setMuted(false)
            } catch {
                // Retry once
                try? await Task.sleep(for: .milliseconds(200))
                try? await self.conversation?.setMuted(false)
            }
        }
    }

    // MARK: - Audio Routing

    /// Set audio session to use loudspeaker by default instead of earpiece.
    /// Respects Bluetooth/headphones when connected.
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            onError?(.unknown("Audio routing failed: \(error.localizedDescription)"))
        }
    }

    // MARK: - Observation

    private func observeConversation(_ conv: Conversation) {
        // Map ElevenLabs agentState → VoiceProviderState
        conv.$agentState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] agentState in
                guard let self, self.conversation != nil else { return }
                switch agentState {
                case .listening:
                    self.state = .listening
                case .speaking:
                    self.state = .speaking
                case .thinking:
                    self.state = .processing
                }
            }
            .store(in: &cancellables)

        // Track connection state
        conv.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] convState in
                guard let self else { return }
                switch convState {
                case .idle:
                    self.state = .idle
                case .connecting:
                    if !self.state.isConnecting {
                        self.state = .connecting(.unknown)
                    }
                case .active:
                    break // agentState handles active substates
                case .ended:
                    self.state = .idle
                    self.conversation = nil
                case .error(let convError):
                    self.onError?(Self.mapError(convError))
                    self.state = .idle
                    self.conversation = nil
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Error Mapping

    private static func mapStartupFailure(_ failure: ConversationStartupFailure) -> VoiceProviderError {
        switch failure {
        case .token(let error):
            return .authenticationFailed(error.localizedDescription)
        case .room(let error):
            return .connectionFailed(error.localizedDescription)
        case .agentTimeout:
            return .agentTimeout
        case .conversationInit(let error):
            return .connectionFailed(error.localizedDescription)
        @unknown default:
            return .unknown("Startup failed")
        }
    }

    private static func mapError(_ error: ConversationError) -> VoiceProviderError {
        switch error {
        case .connectionFailed(let detail):
            return .connectionFailed(detail)
        case .authenticationFailed(let detail):
            return .authenticationFailed(detail)
        case .agentTimeout:
            return .agentTimeout
        case .microphoneToggleFailed(let detail):
            return .microphoneFailure(detail)
        case .notConnected:
            return .connectionFailed("Not connected")
        case .alreadyActive:
            return .unknown("Conversation already active")
        case .localNetworkPermissionRequired:
            return .connectionFailed("Local network permission required")
        @unknown default:
            return .unknown(error.localizedDescription)
        }
    }
}
