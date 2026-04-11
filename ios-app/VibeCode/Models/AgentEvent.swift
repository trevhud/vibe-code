import Foundation

struct AgentEvent: Identifiable, Sendable {
    let id = UUID()
    let priority: Priority
    let category: EventCategory
    let summary: String
    let timestamp: Date
    let sessionId: String
}
