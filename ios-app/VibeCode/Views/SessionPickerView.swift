import SwiftUI

struct SessionPickerView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            if appState.discoveredSessions.isEmpty {
                Spacer()
                if appState.relayClient.connectionState == .connected {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Looking for Claude Code sessions...")
                            .foregroundColor(.secondary)
                    }
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Connecting to relay...")
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(appState.discoveredSessions) { session in
                            SessionRowView(session: session) {
                                appState.selectSession(session)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Sessions")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                connectionBadge
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { appState.reconnect() }) {
                        Label("Reconnect", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button(action: { appState.requestSessions() }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    Button(action: { showingSettings = true }) {
                        Label("Settings", systemImage: "gear")
                    }
                    Button(role: .destructive, action: { Task { await appState.reset() } }) {
                        Label("Disconnect", systemImage: "wifi.slash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(appState)
        }
    }

    @ViewBuilder
    private var connectionBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(statusText)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var statusColor: Color {
        switch appState.relayClient.connectionState {
        case .connected: return .green
        case .connecting, .authenticating, .reconnecting: return .orange
        case .disconnected: return .red
        }
    }

    private var statusText: String {
        switch appState.relayClient.connectionState {
        case .connected: return "Connected"
        case .connecting: return "Connecting..."
        case .authenticating: return "Authenticating..."
        case .reconnecting: return "Reconnecting..."
        case .disconnected: return "Disconnected"
        }
    }
}

struct SessionRowView: View {
    let session: DiscoveredSession
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Status indicator
                VStack {
                    Circle()
                        .fill(session.isActive ? .green : Color(.systemGray4))
                        .frame(width: 10, height: 10)
                }
                .frame(width: 20)

                // Session info
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.projectName)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    Text(abbreviatedPath(session.projectPath))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let timeAgo = relativeTime(from: session.lastActivity) {
                        Text(timeAgo)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                if session.isActive {
                    Text("ACTIVE")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.15))
                        .foregroundColor(.green)
                        .cornerRadius(4)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(Color(.systemGray3))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }

    /// Shorten paths like /Users/username/Code/foo → ~/Code/foo
    private func abbreviatedPath(_ path: String) -> String {
        let home = "/Users/"
        if path.hasPrefix(home) {
            let afterUsers = path.dropFirst(home.count)
            if let slashIndex = afterUsers.firstIndex(of: "/") {
                return "~" + afterUsers[slashIndex...]
            }
        }
        return path
    }

    private func relativeTime(from isoString: String?) -> String? {
        guard let isoString else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoString) else {
            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: isoString) else { return nil }
            return formatRelative(date)
        }
        return formatRelative(date)
    }

    private func formatRelative(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}
