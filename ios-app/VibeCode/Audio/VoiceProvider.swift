import Foundation
import Combine

// MARK: - Voice Provider Error

enum VoiceProviderError: Error, Sendable {
    case notConfigured(String)
    case connectionFailed(String)
    case authenticationFailed(String)
    case agentTimeout
    case microphoneFailure(String)
    case conversationEnded(String)
    case unknown(String)

    var userMessage: String {
        switch self {
        case .notConfigured(let detail):
            return "Not configured: \(detail)"
        case .connectionFailed(let detail):
            return "Connection failed: \(detail)"
        case .authenticationFailed(let detail):
            return "Authentication failed: \(detail)"
        case .agentTimeout:
            return "Agent took too long to connect"
        case .microphoneFailure(let detail):
            return "Microphone error: \(detail)"
        case .conversationEnded(let detail):
            return "Conversation ended: \(detail)"
        case .unknown(let detail):
            return "Error: \(detail)"
        }
    }
}

// MARK: - Voice Provider State

enum VoiceProviderState: Sendable, Equatable {
    case idle
    case connecting(ConnectingPhase)
    case listening
    case speaking
    case processing

    enum ConnectingPhase: Sendable, Equatable {
        case resolvingToken
        case connectingRoom
        case waitingForAgent
        case sendingInit
        case unknown
    }

    var isConnecting: Bool {
        if case .connecting = self { return true }
        return false
    }
}

// MARK: - Voice Provider Protocol

/// Abstraction over the voice pipeline (ElevenLabs, Pipecat, on-device, etc.).
/// VoiceSessionManager depends on this protocol, not a concrete implementation.
@MainActor
protocol VoiceProvider: AnyObject {
    /// Current state of the voice pipeline
    var state: VoiceProviderState { get }

    /// Publisher for state changes (for Combine observation)
    var statePublisher: AnyPublisher<VoiceProviderState, Never> { get }

    /// Whether the conversation session is connected and active
    var isConnected: Bool { get }

    /// Current user transcript (partial, updated in real-time during speech)
    var transcript: String { get }

    /// Publisher for transcript changes
    var transcriptPublisher: AnyPublisher<String, Never> { get }

    /// Begin always-on conversational listening.
    /// The provider handles VAD, STT, and TTS internally.
    func startConversation(sessionId: String) async throws

    /// End the conversation and release resources.
    func endConversation() async

    /// Interrupt any current TTS playback and resume listening.
    func interrupt()

    /// Speak an async event (from JSONL tailer) outside the normal conversation flow.
    /// Implementation should mute the conversation mic during playback to avoid echo.
    func injectSpokenResponse(_ text: String) async

    /// Send a contextual update to the voice agent's LLM.
    /// Used to push Claude Code status changes so the agent can proactively inform the user.
    func sendContextUpdate(_ context: String) async

    /// Called when the user finishes speaking and a final transcript is available.
    /// VoiceSessionManager uses this to know when text was sent to Claude Code.
    var onUserTranscript: ((String) -> Void)? { get set }

    /// Called when an error occurs in the voice pipeline.
    /// VoiceSessionManager hooks this to surface errors in the event log.
    var onError: ((VoiceProviderError) -> Void)? { get set }
}
