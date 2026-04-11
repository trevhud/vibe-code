import XCTest
@testable import VibeCode

final class StateMappingTests: XCTestCase {

    // MARK: - VoiceProviderState

    func testIdleState_isNotConnecting() {
        let state = VoiceProviderState.idle
        XCTAssertFalse(state.isConnecting)
    }

    func testConnectingState_isConnecting() {
        let state = VoiceProviderState.connecting(.unknown)
        XCTAssertTrue(state.isConnecting)
    }

    func testConnectingPhases_areAllConnecting() {
        let phases: [VoiceProviderState.ConnectingPhase] = [
            .resolvingToken, .connectingRoom, .waitingForAgent, .sendingInit, .unknown
        ]
        for phase in phases {
            XCTAssertTrue(VoiceProviderState.connecting(phase).isConnecting)
        }
    }

    func testListeningState_isNotConnecting() {
        XCTAssertFalse(VoiceProviderState.listening.isConnecting)
    }

    func testSpeakingState_isNotConnecting() {
        XCTAssertFalse(VoiceProviderState.speaking.isConnecting)
    }

    func testProcessingState_isNotConnecting() {
        XCTAssertFalse(VoiceProviderState.processing.isConnecting)
    }

    // MARK: - VoiceProviderState Equality

    func testConnectingPhases_areEquatable() {
        XCTAssertEqual(
            VoiceProviderState.connecting(.resolvingToken),
            VoiceProviderState.connecting(.resolvingToken)
        )
        XCTAssertNotEqual(
            VoiceProviderState.connecting(.resolvingToken),
            VoiceProviderState.connecting(.connectingRoom)
        )
    }

    // MARK: - VoiceProviderError

    func testErrorUserMessages() {
        XCTAssertTrue(VoiceProviderError.notConfigured("test").userMessage.contains("Not configured"))
        XCTAssertTrue(VoiceProviderError.connectionFailed("test").userMessage.contains("Connection failed"))
        XCTAssertTrue(VoiceProviderError.authenticationFailed("test").userMessage.contains("Authentication failed"))
        XCTAssertTrue(VoiceProviderError.agentTimeout.userMessage.contains("too long"))
        XCTAssertTrue(VoiceProviderError.microphoneFailure("test").userMessage.contains("Microphone"))
        XCTAssertTrue(VoiceProviderError.conversationEnded("test").userMessage.contains("ended"))
        XCTAssertTrue(VoiceProviderError.unknown("test").userMessage.contains("Error"))
    }
}
