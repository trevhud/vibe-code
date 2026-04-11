import Foundation
import Combine
import Network
import OSLog

@MainActor
class RelayClient: ObservableObject {

    // MARK: - Connection State

    enum ConnectionState: Sendable {
        case disconnected
        case connecting
        case authenticating
        case connected
        case reconnecting
    }

    // MARK: - Published Properties

    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published var lastError: String?

    // MARK: - Event Stream

    let messages = PassthroughSubject<DownstreamMessage, Never>()

    // MARK: - Private State

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var url: String?
    private var token: String?
    private var intentionalDisconnect = false
    private var reconnectAttempt = 0
    private var reconnectTask: Task<Void, Never>?

    private let pathMonitor = NWPathMonitor()
    private var lastPathStatus: NWPath.Status?

    private static let maxBackoff: TimeInterval = 30
    private static let baseBackoff: TimeInterval = 1

    // MARK: - Init

    init() {
        startNetworkMonitor()
    }

    deinit {
        pathMonitor.cancel()
    }

    // MARK: - Public API

    func connect(url: String, token: String) {
        disconnect()

        self.url = url
        self.token = token
        intentionalDisconnect = false
        reconnectAttempt = 0

        openConnection()
    }

    func disconnect() {
        intentionalDisconnect = true
        reconnectTask?.cancel()
        reconnectTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil
        connectionState = .disconnected
    }

    func send(_ message: UpstreamMessage) {
        guard let webSocketTask, connectionState == .connected || connectionState == .authenticating else {
            lastError = "Not connected"
            return
        }

        Task {
            do {
                let data = try JSONEncoder().encode(message)
                guard let text = String(data: data, encoding: .utf8) else { return }
                try await webSocketTask.send(.string(text))
            } catch {
                lastError = "Send failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Convenience Methods

    func requestSessions() {
        send(.sessionListRequest)
    }

    func attach(sessionId: String) {
        send(.attach(sessionId: sessionId))
    }

    func detach() {
        send(.detach)
    }

    func sendInput(sessionId: String, text: String) {
        send(.input(sessionId: sessionId, text: text))
    }

    // MARK: - Connection Internals

    private func openConnection() {
        guard let url, let wsURL = URL(string: url) else {
            lastError = "Invalid URL"
            connectionState = .disconnected
            return
        }

        connectionState = .connecting
        lastError = nil

        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config)
        let task = session!.webSocketTask(with: wsURL)
        webSocketTask = task
        task.resume()

        // Immediately authenticate
        connectionState = .authenticating
        if let token {
            send(.auth(token: token))
        }

        receiveNext()
    }

    private func receiveNext() {
        guard let webSocketTask else { return }

        webSocketTask.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }

                switch result {
                case .success(let message):
                    self.handleMessage(message)
                    self.receiveNext()

                case .failure(let error):
                    if !self.intentionalDisconnect {
                        self.lastError = error.localizedDescription
                        self.scheduleReconnect()
                    }
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let text: String
        switch message {
        case .string(let str):
            text = str
        case .data(let data):
            guard let str = String(data: data, encoding: .utf8) else { return }
            text = str
        @unknown default:
            return
        }

        guard let data = text.data(using: .utf8) else { return }

        do {
            let downstream = try JSONDecoder().decode(DownstreamMessage.self, from: data)

            // Handle auth result to update connection state
            if case .authResult(let success, let error) = downstream {
                if success {
                    connectionState = .connected
                    reconnectAttempt = 0
                } else {
                    lastError = error ?? "Authentication failed"
                    intentionalDisconnect = true // Don't reconnect on auth failure
                    webSocketTask?.cancel(with: .normalClosure, reason: nil)
                    connectionState = .disconnected
                    return
                }
            }

            // Auto-reply pong to ping
            if case .ping = downstream {
                send(.pong)
            }

            messages.send(downstream)
        } catch {
            lastError = "Decode error: \(error.localizedDescription)"
        }
    }

    // MARK: - Reconnection

    private func scheduleReconnect() {
        guard !intentionalDisconnect else { return }

        connectionState = .reconnecting
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil

        reconnectAttempt += 1
        let delay = min(
            Self.baseBackoff * pow(2.0, Double(reconnectAttempt - 1)),
            Self.maxBackoff
        )

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.openConnection()
        }
    }

    // MARK: - Network Change Detection

    private func startNetworkMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let previous = self.lastPathStatus
                self.lastPathStatus = path.status

                // Reconnect when network becomes available (Wi-Fi <-> cellular transition)
                guard path.status == .satisfied,
                      previous != nil,
                      !self.intentionalDisconnect,
                      self.url != nil else { return }

                Logger.relay.info("Network changed, reconnecting")
                self.reconnectAttempt = 0
                self.scheduleReconnect()
            }
        }
        pathMonitor.start(queue: .global(qos: .utility))
    }
}
