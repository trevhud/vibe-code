import SwiftUI

struct ConversationView: View {
    @EnvironmentObject var appState: AppState
    @State private var messageText = ""
    @State private var showingSettings = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Connection Status Bar
                ConnectionStatusBar()
                
                // Messages List
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(appState.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: appState.messages.count) { _ in
                        if let lastMessage = appState.messages.last {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                // Input Area
                MessageInputView(messageText: $messageText) {
                    sendMessage()
                }
            }
            .navigationTitle("Claude Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $appState.showingPasswordInput) {
            if let profile = appState.connectionProfile {
                PasswordInputView(profile: profile) { password in
                    appState.connectWithPassword(password)
                }
            }
        }
    }
    
    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        appState.sendMessage(messageText)
        messageText = ""
    }
}

struct ConnectionStatusBar: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        HStack {
            Circle()
                .fill(appState.connectionStatus.color)
                .frame(width: 8, height: 8)
            
            Text(appState.connectionStatus.description)
                .font(.caption)
                .foregroundColor(.secondary)
            
            if appState.isConnecting {
                ProgressView()
                    .scaleEffect(0.8)
                    .frame(width: 16, height: 16)
            }
            
            Spacer()
            
            if let profile = appState.connectionProfile {
                Text("\(profile.username)@\(profile.host)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }
}

struct MessageBubble: View {
    let message: Message
    
    var body: some View {
        HStack {
            if message.sender.isUser {
                Spacer(minLength: 50)
            }
            
            VStack(alignment: message.sender.isUser ? .trailing : .leading, spacing: 4) {
                if !message.sender.isUser {
                    Text(message.sender.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(message.content)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        message.sender.isUser ? Color.blue : Color(.systemGray5)
                    )
                    .foregroundColor(
                        message.sender.isUser ? .white : .primary
                    )
                    .cornerRadius(18)
                
                Text(formatTime(message.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if !message.sender.isUser {
                Spacer(minLength: 50)
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct MessageInputView: View {
    @Binding var messageText: String
    let onSend: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            TextField("Type your message...", text: $messageText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...6)
                .onSubmit {
                    onSend()
                }
            
            Button {
                onSend()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(.separator)),
            alignment: .top
        )
    }
}

#Preview {
    ConversationView()
        .environmentObject({
            let appState = AppState()
            appState.isSetupComplete = true
            appState.connectionStatus = .connected
            appState.messages = [
                Message(content: "Hello, I need help with my Swift code", sender: .user),
                Message(content: "I'd be happy to help! What specific issue are you encountering with your Swift code?", sender: .claude),
                Message(content: "I'm trying to implement a custom view in SwiftUI", sender: .user)
            ]
            return appState
        }())
}