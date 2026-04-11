import Foundation

struct Message: Identifiable, Codable {
    let id: UUID
    let content: String
    let sender: MessageSender
    let timestamp: Date
    let priority: Priority?

    init(id: UUID = UUID(), content: String, sender: MessageSender, timestamp: Date = Date(), priority: Priority? = nil) {
        self.id = id
        self.content = content
        self.sender = sender
        self.timestamp = timestamp
        self.priority = priority
    }
}

enum MessageSender: String, Codable, CaseIterable {
    case user = "user"
    case claude = "claude"
    case system = "system"

    var displayName: String {
        switch self {
        case .user: return "You"
        case .claude: return "Claude"
        case .system: return "System"
        }
    }

    var isUser: Bool { self == .user }
}
