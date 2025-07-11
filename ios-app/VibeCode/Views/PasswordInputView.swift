import SwiftUI

struct PasswordInputView: View {
    let profile: ConnectionProfile
    let onPasswordProvided: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var password = ""
    @State private var isConnecting = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("Authentication Required")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Enter your Mac password to connect")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 50)
                
                Spacer()
                
                // Connection Details
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Host:")
                        Spacer()
                        Text(profile.host)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Username:")
                        Spacer()
                        Text(profile.username)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Session:")
                        Spacer()
                        Text(profile.sessionName)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // Password Input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mac Password")
                        .font(.headline)
                    
                    SecureField("Enter your password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            if !password.isEmpty {
                                connectWithPassword()
                            }
                        }
                    
                    Text("This is the password you use to log into your Mac")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Action Buttons
                VStack(spacing: 16) {
                    Button(action: connectWithPassword) {
                        HStack {
                            if isConnecting {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Connecting...")
                            } else {
                                Image(systemName: "link")
                                Text("Connect")
                            }
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(password.isEmpty ? Color.gray : Color.blue)
                        .cornerRadius(25)
                    }
                    .disabled(password.isEmpty || isConnecting)
                    
                    Button("Use SSH Key Instead") {
                        // TODO: Implement SSH key authentication
                        errorMessage = "SSH key authentication not yet implemented. Please use password authentication."
                        showingError = true
                    }
                    .foregroundColor(.blue)
                    .disabled(isConnecting)
                }
                .padding(.horizontal)
                .padding(.bottom, 50)
            }
            .navigationTitle("Authentication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isConnecting)
                }
            }
        }
        .alert("Connection Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func connectWithPassword() {
        guard !password.isEmpty else { return }
        
        isConnecting = true
        
        // Store password securely
        let settingsManager = SettingsManager()
        if settingsManager.storePassword(password, for: profile.username) {
            onPasswordProvided(password)
            dismiss()
        } else {
            errorMessage = "Failed to store password securely"
            showingError = true
            isConnecting = false
        }
    }
}

#Preview {
    PasswordInputView(
        profile: ConnectionProfile(
            host: "100.64.1.2",
            port: 22,
            username: "user",
            sessionName: "claude-vibe-code",
            created: Date()
        ),
        onPasswordProvided: { _ in }
    )
}