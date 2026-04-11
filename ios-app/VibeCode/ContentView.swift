import SwiftUI

struct ContentView: View {
    @StateObject private var appState = AppState()

    var body: some View {
        Group {
            if appState.phase == .setup {
                SetupView()
            } else {
                NavigationStack(path: $appState.navigationPath) {
                    SessionPickerView()
                        .navigationDestination(for: String.self) { _ in
                            VoiceView()
                        }
                }
            }
        }
        .environmentObject(appState)
    }
}

#Preview {
    ContentView()
}
