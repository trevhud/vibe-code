import Foundation
import Combine
@testable import VibeCode

@MainActor
final class MockVoiceProvider: VoiceProvider {
    // MARK: - State

    @Published private(set) var state: VoiceProviderState = .idle
    var transcript: String = ""

    var statePublisher: AnyPublisher<VoiceProviderState, Never> {
        $state.eraseToAnyPublisher()
    }

    var transcriptPublisher: AnyPublisher<String, Never> {
        Just(transcript).eraseToAnyPublisher()
    }

    var isConnected: Bool = false

    var onUserTranscript: ((String) -> Void)?
    var onError: ((VoiceProviderError) -> Void)?

    // MARK: - Tracking

    var startConversationCalled = false
    var startConversationSessionId: String?
    var endConversationCalled = false
    var endConversationCallCount = 0
    var interruptCalled = false
    var sendContextUpdateCalled = false
    var sendContextUpdateText: String?
    var injectSpokenResponseCalled = false
    var injectSpokenResponseText: String?

    var startConversationError: Error?

    // MARK: - VoiceProvider

    func startConversation(sessionId: String) async throws {
        startConversationCalled = true
        startConversationSessionId = sessionId
        if let error = startConversationError {
            throw error
        }
        state = .listening
    }

    func endConversation() async {
        endConversationCalled = true
        endConversationCallCount += 1
        state = .idle
    }

    func interrupt() {
        interruptCalled = true
    }

    func injectSpokenResponse(_ text: String) async {
        injectSpokenResponseCalled = true
        injectSpokenResponseText = text
    }

    func sendContextUpdate(_ context: String) async {
        sendContextUpdateCalled = true
        sendContextUpdateText = context
    }

    // MARK: - Test Helpers

    func simulateStateChange(_ newState: VoiceProviderState) {
        state = newState
    }

    func reset() {
        startConversationCalled = false
        startConversationSessionId = nil
        endConversationCalled = false
        endConversationCallCount = 0
        interruptCalled = false
        sendContextUpdateCalled = false
        sendContextUpdateText = nil
        injectSpokenResponseCalled = false
        injectSpokenResponseText = nil
        startConversationError = nil
        state = .idle
        transcript = ""
    }
}
