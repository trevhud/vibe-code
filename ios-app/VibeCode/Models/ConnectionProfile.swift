import Foundation

struct ConnectionProfile: Codable, Identifiable {
    let id: UUID
    let relayUrl: String
    let token: String
    let hostname: String
    let created: Date

    init(relayUrl: String, token: String, hostname: String = "", created: Date = Date()) {
        self.id = UUID()
        self.relayUrl = relayUrl
        self.token = token
        self.hostname = hostname
        self.created = created
    }

    private enum CodingKeys: String, CodingKey {
        case relayUrl, token, hostname, created
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.relayUrl = try container.decode(String.self, forKey: .relayUrl)
        self.token = try container.decode(String.self, forKey: .token)
        self.hostname = try container.decodeIfPresent(String.self, forKey: .hostname) ?? ""
        self.created = try container.decodeIfPresent(Date.self, forKey: .created) ?? Date()
    }
}

/// QR code payload from relay server's /pair/json endpoint
struct QRPayload: Codable {
    let relayUrl: String
    let token: String
    let hostname: String

    func toConnectionProfile() -> ConnectionProfile {
        ConnectionProfile(relayUrl: relayUrl, token: token, hostname: hostname)
    }
}
