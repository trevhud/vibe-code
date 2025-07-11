import SwiftUI

struct SessionPickerView: View {
    let payload: ConnectionPayload
    let onSessionSelected: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "folder.fill.badge.person.crop")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("Choose Session")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Select which project to connect to")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 30)
                
                Spacer()
                
                // Session List
                VStack(spacing: 16) {
                    ForEach(payload.sessionOptions, id: \.self) { sessionName in
                        SessionRowView(
                            sessionName: sessionName,
                            isRecommended: sessionName == payload.sessionName
                        ) {
                            onSessionSelected(sessionName)
                            dismiss()
                        }
                    }
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Connection Info
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "network")
                        Text("Host: \(payload.host)")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    
                    HStack {
                        Image(systemName: "person.circle")
                        Text("User: \(payload.username)")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
            .navigationTitle("Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct SessionRowView: View {
    let sessionName: String
    let isRecommended: Bool
    let onTap: () -> Void
    
    private var folderName: String {
        if sessionName.hasPrefix("claude-") {
            return String(sessionName.dropFirst(7))
        }
        return sessionName
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Folder Icon
                Image(systemName: "folder.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 32)
                
                // Session Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(folderName)
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        if isRecommended {
                            Text("RECOMMENDED")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(4)
                        }
                    }
                    
                    Text(sessionName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    SessionPickerView(
        payload: ConnectionPayload(
            host: "100.64.1.2",
            port: 22,
            username: "user",
            sessionName: "claude-vibe-code",
            created: Date(),
            availableSessions: [
                "claude-vibe-code",
                "claude-soundtrak", 
                "claude-lightning-list"
            ]
        ),
        onSessionSelected: { _ in }
    )
}