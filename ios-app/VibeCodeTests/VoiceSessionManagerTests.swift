import XCTest
import Combine
@testable import VibeCode

@MainActor
final class VoiceSessionManagerTests: XCTestCase {

    private var mockProvider: MockVoiceProvider!
    private var relayClient: RelayClient!
    private var ttsProvider: AppleTTSProvider!
    private var sut: VoiceSessionManager!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        mockProvider = MockVoiceProvider()
        relayClient = RelayClient()
        ttsProvider = AppleTTSProvider()
        sut = VoiceSessionManager(
            relayClient: relayClient,
            voiceProvider: mockProvider,
            fallbackTTS: ttsProvider
        )
        cancellables = []
    }

    override func tearDown() async throws {
        cancellables = nil
        sut = nil
        mockProvider = nil
        relayClient = nil
        ttsProvider = nil
    }

    // MARK: - startConversation

    func testStartConversation_requiresSessionId() async throws {
        // No session attached — startConversation should be a no-op
        try await sut.startConversation()
        XCTAssertFalse(mockProvider.startConversationCalled)
    }

    func testStartConversation_callsProvider() async throws {
        sut.attachToSession("session-123")
        try await sut.startConversation()

        XCTAssertTrue(mockProvider.startConversationCalled)
        XCTAssertEqual(mockProvider.startConversationSessionId, "session-123")
    }

    // MARK: - endConversation

    func testEndConversation_callsProvider() async {
        sut.attachToSession("session-123")
        await sut.endConversation()

        XCTAssertTrue(mockProvider.endConversationCalled)
    }

    // MARK: - detach

    func testDetach_awaitsAndClearsState() async {
        sut.attachToSession("session-123")
        XCTAssertEqual(sut.currentSessionId, "session-123")

        await sut.detach()

        XCTAssertTrue(mockProvider.endConversationCalled)
        XCTAssertNil(sut.currentSessionId)
        XCTAssertTrue(sut.eventLog.isEmpty)
    }

    func testDoubleDetach_idempotent() async {
        sut.attachToSession("session-123")

        // First detach clears state
        await sut.detach()
        XCTAssertTrue(mockProvider.endConversationCalled)
        XCTAssertNil(sut.currentSessionId)

        // Second detach is safe — no crash, state stays cleared
        await sut.detach()
        XCTAssertNil(sut.currentSessionId)
        XCTAssertEqual(mockProvider.endConversationCallCount, 2)
    }

    // MARK: - Context Update Forwarding

    func testContextUpdate_forwardsToProvider() async {
        sut.attachToSession("session-123")

        // Simulate a context_update from the relay
        relayClient.messages.send(.contextUpdate(sessionId: "session-123", context: "Agent is thinking about your code"))

        // Give the async Task in handleDownstreamMessage time to execute
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertTrue(mockProvider.sendContextUpdateCalled)
        XCTAssertEqual(mockProvider.sendContextUpdateText, "Agent is thinking about your code")
    }

    // MARK: - Voice State Forwarding

    func testVoiceStateForwarding() async {
        let expectation = XCTestExpectation(description: "State forwarded")

        sut.$voiceState
            .dropFirst() // Skip initial .idle
            .sink { state in
                if state == .listening {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        mockProvider.simulateStateChange(.listening)

        await fulfillment(of: [expectation], timeout: 2)
        XCTAssertEqual(sut.voiceState, .listening)
    }

    // MARK: - Error Forwarding

    func testErrorForwarding_addsSystemEvent() {
        // Trigger the onError callback that VoiceSessionManager registered
        mockProvider.onError?(.connectionFailed("Test error"))

        XCTAssertEqual(sut.eventLog.count, 1)
        XCTAssertTrue(sut.eventLog[0].summary.contains("Connection failed"))
    }

    // MARK: - Agent Event Handling

    func testAgentEvent_insertsIntoLog() async {
        sut.attachToSession("session-123")

        relayClient.messages.send(.agentEvent(
            sessionId: "session-123",
            priority: .queue,
            category: .progress,
            summary: "Running tests...",
            timestamp: ISO8601DateFormatter().string(from: Date())
        ))

        // Give the DispatchQueue.main sink time to process
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(sut.eventLog.count, 1)
        XCTAssertEqual(sut.eventLog[0].summary, "Running tests...")
        XCTAssertEqual(sut.eventLog[0].priority, .queue)
    }
}
