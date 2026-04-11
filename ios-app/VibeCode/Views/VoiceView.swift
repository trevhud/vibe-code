import SwiftUI

struct VoiceView: View {
    @EnvironmentObject var appState: AppState
    @State private var connectingElapsed: Int = 0
    @State private var connectingTimer: Timer?

    var body: some View {
        let vsm = appState.voiceSessionManager

        VStack(spacing: 0) {
            // Compact header: connection + voice state + button
            HStack(spacing: 12) {
                // Voice state indicator (compact)
                compactVoiceState(vsm: vsm)

                Spacer()

                // Conversation toggle button (compact)
                compactConversationButton(vsm: vsm)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color(.systemGray6))

            // Full-screen event stream
            eventStream(vsm: vsm)
        }
        .navigationTitle(appState.selectedSession?.projectName ?? "Voice")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { appState.reconnect() }) {
                        Label("Reconnect", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button(action: { Task { await appState.goBackToSessionPicker() } }) {
                        Label("Sessions", systemImage: "list.bullet")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onChange(of: appState.voiceSessionManager.voiceState) { _, newState in
            if newState.isConnecting {
                connectingElapsed = 0
                connectingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                    Task { @MainActor in
                        connectingElapsed += 1
                    }
                }
            } else {
                connectingTimer?.invalidate()
                connectingTimer = nil
            }
        }
        .onDisappear {
            connectingTimer?.invalidate()
            connectingTimer = nil
        }
        .onAppear {
            let vsm = appState.voiceSessionManager
            if vsm.voiceState == .idle && appState.hasAgentId {
                Task {
                    try? await vsm.startConversation()
                }
            }
        }
    }

    // MARK: - Compact Voice State

    @ViewBuilder
    private func compactVoiceState(vsm: VoiceSessionManager) -> some View {
        HStack(spacing: 8) {
            // Connection dot
            Circle()
                .fill(appState.relayClient.connectionState == .connected ? .green : .orange)
                .frame(width: 8, height: 8)

            // Voice state icon + label
            switch vsm.voiceState {
            case .idle:
                Image(systemName: "waveform.circle")
                    .foregroundColor(.gray)
                Text("Voice off")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

            case .connecting(let phase):
                ProgressView()
                    .scaleEffect(0.7)
                Text(connectingPhaseText(phase))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

            case .listening:
                Image(systemName: "waveform.circle.fill")
                    .foregroundColor(.blue)
                    .symbolEffect(.pulse)
                Text(vsm.transcript.isEmpty ? "Listening..." : vsm.transcript)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(1)

            case .processing:
                Image(systemName: "brain")
                    .foregroundColor(.purple)
                    .symbolEffect(.pulse)
                Text("Thinking...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

            case .speaking:
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundColor(.green)
                    .symbolEffect(.variableColor)
                Text("Speaking...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func connectingPhaseText(_ phase: VoiceProviderState.ConnectingPhase) -> String {
        switch phase {
        case .resolvingToken: return "Authenticating..."
        case .connectingRoom: return "Connecting room..."
        case .waitingForAgent: return "Waiting for agent..."
        case .sendingInit: return "Initializing..."
        case .unknown: return "Connecting..."
        }
    }

    // MARK: - Compact Conversation Button

    @ViewBuilder
    private func compactConversationButton(vsm: VoiceSessionManager) -> some View {
        let isActive = vsm.voiceState != .idle

        Button(action: {
            Task {
                if isActive {
                    await vsm.endConversation()
                } else {
                    try? await vsm.startConversation()
                }
            }
        }) {
            Image(systemName: isActive ? "stop.circle.fill" : "phone.circle.fill")
                .font(.system(size: 32))
                .foregroundColor(isActive ? .red : .blue)
        }
        .disabled(vsm.voiceState.isConnecting)
    }

    // MARK: - Full-Screen Event Stream

    @ViewBuilder
    private func eventStream(vsm: VoiceSessionManager) -> some View {
        if vsm.eventLog.isEmpty {
            VStack {
                Spacer()
                Text("waiting for events...")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(vsm.eventLog) { event in
                            StreamRow(event: event)
                                .id(event.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onChange(of: vsm.eventLog.first?.id) { _, newId in
                    if let newId {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(newId, anchor: .top)
                        }
                    }
                }
            }
        }
    }
}

struct StreamRow: View {
    let event: AgentEvent

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        Text(event.summary)
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
