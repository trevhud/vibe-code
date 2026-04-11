import Foundation

// MARK: - Shared Types

enum Priority: String, Codable, Sendable {
    case interrupt
    case queue
    case silent
}

enum EventCategory: String, Codable, Sendable {
    case question
    case error
    case completion
    case permission
    case progress
}

enum SessionState: String, Codable, Sendable {
    case active
    case idle
    case disconnected
}

struct DiscoveredSession: Codable, Identifiable, Sendable {
    let id: String
    let projectPath: String
    let projectName: String
    let tmuxSession: String?
    let lastActivity: String?
    let isActive: Bool
}

// MARK: - Upstream Messages (Phone → Relay)

enum UpstreamMessage: Encodable, Sendable {
    case auth(token: String)
    case input(sessionId: String, text: String)
    case sessionListRequest
    case attach(sessionId: String)
    case detach
    case pong

    private enum CodingKeys: String, CodingKey {
        case type
        case token
        case sessionId
        case text
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .auth(let token):
            try container.encode("auth", forKey: .type)
            try container.encode(token, forKey: .token)
        case .input(let sessionId, let text):
            try container.encode("input", forKey: .type)
            try container.encode(sessionId, forKey: .sessionId)
            try container.encode(text, forKey: .text)
        case .sessionListRequest:
            try container.encode("session_list_request", forKey: .type)
        case .attach(let sessionId):
            try container.encode("attach", forKey: .type)
            try container.encode(sessionId, forKey: .sessionId)
        case .detach:
            try container.encode("detach", forKey: .type)
        case .pong:
            try container.encode("pong", forKey: .type)
        }
    }
}

// MARK: - Downstream Messages (Relay → Phone)

struct HistoryEvent: Codable, Sendable {
    let priority: Priority
    let category: EventCategory
    let summary: String
    let timestamp: String
}

enum DownstreamMessage: Sendable {
    case authResult(success: Bool, error: String?)
    case sessionList(sessions: [DiscoveredSession])
    case agentEvent(sessionId: String, priority: Priority, category: EventCategory, summary: String, timestamp: String)
    case inputAck(sessionId: String, success: Bool, error: String?)
    case sessionState(sessionId: String, state: SessionState)
    case sessionHistory(sessionId: String, events: [HistoryEvent])
    case contextUpdate(sessionId: String, context: String)
    case ping
}

extension DownstreamMessage: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type
        case success
        case error
        case sessions
        case sessionId
        case priority
        case category
        case summary
        case timestamp
        case state
        case events
        case context
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "auth_result":
            let success = try container.decode(Bool.self, forKey: .success)
            let error = try container.decodeIfPresent(String.self, forKey: .error)
            self = .authResult(success: success, error: error)

        case "session_list":
            let sessions = try container.decode([DiscoveredSession].self, forKey: .sessions)
            self = .sessionList(sessions: sessions)

        case "agent_event":
            let sessionId = try container.decode(String.self, forKey: .sessionId)
            let priority = try container.decode(Priority.self, forKey: .priority)
            let category = try container.decode(EventCategory.self, forKey: .category)
            let summary = try container.decode(String.self, forKey: .summary)
            let timestamp = try container.decode(String.self, forKey: .timestamp)
            self = .agentEvent(sessionId: sessionId, priority: priority, category: category, summary: summary, timestamp: timestamp)

        case "input_ack":
            let sessionId = try container.decode(String.self, forKey: .sessionId)
            let success = try container.decode(Bool.self, forKey: .success)
            let error = try container.decodeIfPresent(String.self, forKey: .error)
            self = .inputAck(sessionId: sessionId, success: success, error: error)

        case "session_state":
            let sessionId = try container.decode(String.self, forKey: .sessionId)
            let state = try container.decode(SessionState.self, forKey: .state)
            self = .sessionState(sessionId: sessionId, state: state)

        case "session_history":
            let sessionId = try container.decode(String.self, forKey: .sessionId)
            let events = try container.decode([HistoryEvent].self, forKey: .events)
            self = .sessionHistory(sessionId: sessionId, events: events)

        case "context_update":
            let sessionId = try container.decode(String.self, forKey: .sessionId)
            let context = try container.decode(String.self, forKey: .context)
            self = .contextUpdate(sessionId: sessionId, context: context)

        case "ping":
            self = .ping

        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [CodingKeys.type],
                    debugDescription: "Unknown message type: \(type)"
                )
            )
        }
    }
}
