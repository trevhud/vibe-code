import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @State private var showingResetAlert = false
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Connection")) {
                    if let profile = appState.connectionProfile {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Host")
                                Spacer()
                                Text(profile.host)
                                    .foregroundColor(.secondary)
                            }
                            
                            HStack {
                                Text("Username")
                                Spacer()
                                Text(profile.username)
                                    .foregroundColor(.secondary)
                            }
                            
                            HStack {
                                Text("Session")
                                Spacer()
                                Text(profile.sessionName)
                                    .foregroundColor(.secondary)
                            }
                            
                            HStack {
                                Text("Created")
                                Spacer()
                                Text(formatDate(profile.created))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    HStack {
                        Image(systemName: "circle.fill")
                            .foregroundColor(appState.connectionStatus.color)
                        Text("Status")
                        Spacer()
                        Text(appState.connectionStatus.description)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Actions")) {
                    Button("Reconnect") {
                        appState.connectToSession()
                    }
                    .disabled(appState.isConnecting)
                    
                    Button("Reset Setup") {
                        showingResetAlert = true
                    }
                    .foregroundColor(.red)
                }
                
                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    Link("Vibe Code on GitHub", destination: URL(string: "https://github.com/your-repo/vibe-code")!)
                        .foregroundColor(.blue)
                    
                    Link("Support", destination: URL(string: "https://github.com/your-repo/vibe-code/issues")!)
                        .foregroundColor(.blue)
                }
                
                Section(header: Text("Instructions")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("To use Vibe Code:")
                            .fontWeight(.semibold)
                        
                        Text("1. Install Tailscale on both Mac and iPhone")
                        Text("2. Run 'vibe-code setup' on your Mac")
                        Text("3. Run 'vibe-code connect' to show QR code")
                        Text("4. Scan QR code with this app")
                        Text("5. Continue your Claude conversations anywhere!")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .alert("Reset Setup", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                appState.reset()
                dismiss()
            }
        } message: {
            Text("This will clear your connection settings and return to the setup screen. You'll need to scan the QR code again.")
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    SettingsView()
        .environmentObject({
            let appState = AppState()
            appState.isSetupComplete = true
            appState.connectionStatus = .connected
            return appState
        }())
}