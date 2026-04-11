import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @State private var showingResetAlert = false
    @State private var agentId: String = ""
    @State private var relayUrl: String = ""

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Connection")) {
                    if appState.connectionProfile != nil {
                        VStack(alignment: .leading) {
                            Text("Relay URL")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField(AppConstants.exampleRelayUrl, text: $relayUrl)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .keyboardType(.URL)
                                .onSubmit {
                                    guard !relayUrl.isEmpty, relayUrl.hasPrefix("ws") else { return }
                                    appState.updateRelayUrl(relayUrl)
                                }
                        }
                    }

                    HStack {
                        Circle()
                            .fill(appState.relayClient.connectionState == .connected ? .green : .orange)
                            .frame(width: 8, height: 8)
                        Text("Status")
                        Spacer()
                        Text(connectionStateText)
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("ElevenLabs"), footer: Text("Agent ID for conversational voice. Create one at elevenlabs.io with a custom LLM pointing to your relay's /v1/chat/completions.")) {
                    TextField("Agent ID", text: $agentId)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onSubmit {
                            appState.settingsManager.elevenLabsAgentId = agentId.isEmpty ? nil : agentId
                        }
                        .onChange(of: agentId) { _, newValue in
                            appState.settingsManager.elevenLabsAgentId = newValue.isEmpty ? nil : newValue
                        }
                }

                Section(header: Text("Actions")) {
                    Button("Reconnect") {
                        appState.reconnect()
                    }

                    Button("Reset Setup") {
                        showingResetAlert = true
                    }
                    .foregroundColor(.red)
                }

                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(AppConstants.appVersion)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            agentId = appState.settingsManager.elevenLabsAgentId ?? ""
            relayUrl = appState.connectionProfile?.relayUrl ?? ""
        }
        .alert("Reset Setup", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                Task {
                    await appState.reset()
                    dismiss()
                }
            }
        } message: {
            Text("This will clear your connection settings and return to the setup screen.")
        }
    }

    private var connectionStateText: String {
        switch appState.relayClient.connectionState {
        case .connected: return "Connected"
        case .connecting: return "Connecting..."
        case .authenticating: return "Authenticating..."
        case .reconnecting: return "Reconnecting..."
        case .disconnected: return "Disconnected"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
