import Foundation
import Network
import NIO
import NIOSSH

@MainActor
class ConnectionManager: ObservableObject {
    private var eventLoopGroup: EventLoopGroup?
    private var channel: Channel?
    private var isConnected = false
    private var currentProfile: ConnectionProfile?
    private var tmuxHandler: TmuxHandler?
    
    // Delegate for receiving messages
    weak var delegate: ConnectionManagerDelegate?
    
    func connect(to profile: ConnectionProfile) async throws {
        currentProfile = profile
        
        // Initialize NIO event loop group
        eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        
        guard let eventLoopGroup = eventLoopGroup else {
            throw ConnectionError.initializationFailed
        }
        
        // Create SSH client configuration
        let bootstrap = ClientBootstrap(group: eventLoopGroup)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
                let sshHandler = NIOSSHHandler(
                    role: .client(.init(
                        userAuthDelegate: PasswordAuthDelegate(
                            username: profile.username,
                            password: self.getStoredPassword(for: profile)
                        ),
                        serverAuthDelegate: AcceptAllHostKeysDelegate()
                    )),
                    allocator: channel.allocator,
                    inboundChildChannelInitializer: { childChannel, channelType in
                        // Handle SSH child channels (exec, shell, etc.)
                        switch channelType {
                        case .session:
                            return childChannel.pipeline.addHandler(
                                TmuxChannelHandler(profile: profile, delegate: self)
                            )
                        default:
                            return childChannel.eventLoop.makeSucceededFuture(())
                        }
                    }
                )
                
                return channel.pipeline.addHandler(sshHandler)
            }
        
        do {
            // Connect to the host
            channel = try await bootstrap.connect(host: profile.host, port: profile.port).get()
            isConnected = true
            
            // Wait for SSH connection to be fully established
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
        } catch {
            isConnected = false
            throw ConnectionError.connectionFailed(error.localizedDescription)
        }
    }
    
    func sendInput(_ text: String) async throws {
        guard isConnected, let tmuxHandler = tmuxHandler else {
            throw ConnectionError.notConnected
        }
        
        try await tmuxHandler.sendInput(text + "\n")
    }
    
    func disconnect() {
        tmuxHandler?.disconnect()
        tmuxHandler = nil
        
        channel?.close(promise: nil)
        channel = nil
        isConnected = false
        
        do {
            try eventLoopGroup?.syncShutdownGracefully()
        } catch {
            print("Error shutting down event loop group: \(error)")
        }
        eventLoopGroup = nil
    }
    
    private func getStoredPassword(for profile: ConnectionProfile) -> String {
        let settingsManager = SettingsManager()
        return settingsManager.retrievePassword(for: profile.username) ?? ""
    }
    
    deinit {
        disconnect()
    }
}

// MARK: - SSH Channel Delegate

extension ConnectionManager: SSHChannelDelegate {
    func sshChannelEstablished(_ handler: TmuxHandler) {
        self.tmuxHandler = handler
        
        Task { @MainActor in
            // Attach to tmux session
            try await handler.attachToSession(currentProfile?.sessionName ?? "claude-code")
        }
    }
    
    func sshChannelClosed() {
        tmuxHandler = nil
        isConnected = false
    }
    
    func receivedOutput(_ output: String) {
        delegate?.connectionManager(self, receivedOutput: output)
    }
}

// MARK: - Protocols

protocol ConnectionManagerDelegate: AnyObject {
    func connectionManager(_ manager: ConnectionManager, receivedOutput output: String)
}

protocol SSHChannelDelegate: AnyObject {
    func sshChannelEstablished(_ handler: TmuxHandler)
    func sshChannelClosed()
    func receivedOutput(_ output: String)
}

// MARK: - SSH Authentication

class PasswordAuthDelegate: NIOSSHClientUserAuthenticationDelegate {
    private let username: String
    private let password: String
    
    init(username: String, password: String) {
        self.username = username
        self.password = password
    }
    
    func nextAuthenticationType(availableMethods: NIOSSHAvailableUserAuthenticationMethods, nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>) {
        if availableMethods.contains(.password) {
            nextChallengePromise.succeed(.init(username: username, serviceName: "", offer: .password(.init(password: password))))
        } else {
            nextChallengePromise.succeed(nil)
        }
    }
}

class AcceptAllHostKeysDelegate: NIOSSHClientServerAuthenticationDelegate {
    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        // For development purposes, accept all host keys
        // In production, this should validate against known hosts
        validationCompletePromise.succeed(())
    }
}

// MARK: - Tmux Channel Handler

class TmuxChannelHandler: ChannelInboundHandler {
    typealias InboundIn = SSHChannelData
    typealias OutboundOut = SSHChannelData
    
    private let profile: ConnectionProfile
    private weak var delegate: SSHChannelDelegate?
    private var tmuxHandler: TmuxHandler?
    
    init(profile: ConnectionProfile, delegate: SSHChannelDelegate?) {
        self.profile = profile
        self.delegate = delegate
    }
    
    func channelActive(context: ChannelHandlerContext) {
        // Request a shell session
        let shellRequest = SSHChannelRequestEvent.ShellRequest(wantReply: false)
        context.triggerUserOutboundEvent(shellRequest, promise: nil)
        
        // Create tmux handler
        tmuxHandler = TmuxHandler(channel: context.channel, delegate: delegate)
        delegate?.sshChannelEstablished(tmuxHandler!)
    }
    
    func channelInactive(context: ChannelHandlerContext) {
        delegate?.sshChannelClosed()
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = unwrapInboundIn(data)
        
        switch channelData.data {
        case .byteBuffer(let buffer):
            if let string = buffer.getString(at: 0, length: buffer.readableBytes) {
                delegate?.receivedOutput(string)
            }
        case .channel:
            break
        }
    }
}

// MARK: - Tmux Handler

class TmuxHandler {
    private let channel: Channel
    private weak var delegate: SSHChannelDelegate?
    private var isAttached = false
    
    init(channel: Channel, delegate: SSHChannelDelegate?) {
        self.channel = channel
        self.delegate = delegate
    }
    
    func attachToSession(_ sessionName: String) async throws {
        let command = "tmux attach-session -t \(sessionName)\n"
        try await sendCommand(command)
        isAttached = true
    }
    
    func sendInput(_ input: String) async throws {
        guard isAttached else {
            throw ConnectionError.sessionAttachmentFailed
        }
        
        try await sendCommand(input)
    }
    
    private func sendCommand(_ command: String) async throws {
        var buffer = channel.allocator.buffer(capacity: command.utf8.count)
        buffer.writeString(command)
        
        let channelData = SSHChannelData(
            type: .channel,
            data: .byteBuffer(buffer)
        )
        
        try await channel.writeAndFlush(channelData)
    }
    
    func disconnect() {
        isAttached = false
    }
}

enum ConnectionError: Error, LocalizedError {
    case initializationFailed
    case connectionFailed(String)
    case authenticationFailed
    case notConnected
    case sessionAttachmentFailed
    
    var errorDescription: String? {
        switch self {
        case .initializationFailed:
            return "Failed to initialize connection"
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .authenticationFailed:
            return "Authentication failed"
        case .notConnected:
            return "Not connected"
        case .sessionAttachmentFailed:
            return "Failed to attach to tmux session"
        }
    }
}