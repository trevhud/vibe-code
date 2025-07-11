import SwiftUI

struct ContentView: View {
    @StateObject private var appState = AppState()
    
    var body: some View {
        Group {
            if appState.isSetupComplete {
                ConversationView()
            } else {
                SetupView()
            }
        }
        .environmentObject(appState)
    }
}

#Preview {
    ContentView()
}