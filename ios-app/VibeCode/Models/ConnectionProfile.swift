import Foundation

struct ConnectionProfile: Codable, Identifiable {
    let id = UUID()
    let host: String
    let port: Int
    let username: String
    let sessionName: String
    let created: Date
    
    private enum CodingKeys: String, CodingKey {
        case host, port, username, sessionName, created
    }
}

struct ConnectionPayload: Codable {
    let host: String
    let port: Int
    let username: String
    let sessionName: String
    let created: Date
    let availableSessions: [String]?
    
    func toConnectionProfile(selectedSession: String? = nil) -> ConnectionProfile {
        return ConnectionProfile(
            host: host,
            port: port,
            username: username,
            sessionName: selectedSession ?? sessionName,
            created: created
        )
    }
    
    var hasMultipleSessions: Bool {
        return (availableSessions?.count ?? 0) > 1
    }
    
    var sessionOptions: [String] {
        return availableSessions ?? [sessionName]
    }
}