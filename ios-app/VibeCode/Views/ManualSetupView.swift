import SwiftUI

struct ManualSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    @State private var host = ""
    @State private var port = "22"
    @State private var username = ""
    @State private var sessionName = "claude-code"
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Connection Details")) {
                    HStack {
                        Text("Host IP")
                        Spacer()
                        TextField("100.64.1.2", text: $host)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)
                    }
                    
                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("22", text: $port)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                            .frame(width: 80)
                    }
                    
                    HStack {
                        Text("Username")
                        Spacer()
                        TextField("username", text: $username)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    
                    HStack {
                        Text("Session Name")
                        Spacer()
                        TextField("claude-code", text: $sessionName)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                }
                
                Section(header: Text("Instructions")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("1. Get your Tailscale IP:")
                            .fontWeight(.semibold)
                        Text("Run 'tailscale ip -4' on your Mac")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("2. Get your username:")
                            .fontWeight(.semibold)
                        Text("Run 'whoami' on your Mac")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("3. Ensure Vibe Code is set up:")
                            .fontWeight(.semibold)
                        Text("Run 'vibe-code setup' on your Mac first")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                
                Section {
                    Button("Connect") {
                        connectManually()
                    }
                    .disabled(!isFormValid)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Manual Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .alert("Connection Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private var isFormValid: Bool {
        !host.isEmpty && !port.isEmpty && !username.isEmpty && !sessionName.isEmpty
    }
    
    private func connectManually() {
        guard let portInt = Int(port) else {
            errorMessage = "Invalid port number"
            showingError = true
            return
        }
        
        let profile = ConnectionProfile(
            host: host,
            port: portInt,
            username: username,
            sessionName: sessionName,
            created: Date()
        )
        
        appState.setupConnection(with: profile)
        dismiss()
    }
}

#Preview {
    ManualSetupView()
        .environmentObject(AppState())
}