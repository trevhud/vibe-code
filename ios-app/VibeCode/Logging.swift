import OSLog

extension Logger {
    static let voice = Logger(subsystem: "com.vibecode.app", category: "voice")
    static let relay = Logger(subsystem: "com.vibecode.app", category: "relay")
    static let settings = Logger(subsystem: "com.vibecode.app", category: "settings")
}
