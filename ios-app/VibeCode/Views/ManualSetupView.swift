import SwiftUI

struct ManualSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    @State private var relayUrl = ""
    @State private var token = ""
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Relay Server")) {
                    VStack(alignment: .leading) {
                        Text("Relay URL")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField(AppConstants.exampleRelayUrl, text: $relayUrl)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .keyboardType(.URL)
                    }

                    VStack(alignment: .leading) {
                        Text("Token")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Paste JWT token", text: $token)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                }

                Section(header: Text("Instructions")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("1. Start the relay server:")
                            .fontWeight(.semibold)
                        Text("cd relay-server && npm run dev")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("2. Get the connection info:")
                            .fontWeight(.semibold)
                        Text("curl <your-mac>:3578/pair/json")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("3. Copy relayUrl and token above")
                            .fontWeight(.semibold)
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
                    Button("Cancel") { dismiss() }
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
        !relayUrl.isEmpty && !token.isEmpty && relayUrl.hasPrefix("ws")
    }

    private func connectManually() {
        let profile = ConnectionProfile(relayUrl: relayUrl, token: token)
        appState.setupConnection(with: profile)
        dismiss()
    }
}
