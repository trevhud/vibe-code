import SwiftUI
import AVFoundation
import OSLog

struct SetupView: View {
    @EnvironmentObject var appState: AppState
    @State private var isShowingQRScanner = false
    @State private var showingManualSetup = false
    @State private var hasPermission = false

    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                VStack(spacing: 16) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)

                    Text("Vibe Code")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Voice-first Claude Code on the go")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 50)

                Spacer()

                VStack(alignment: .leading, spacing: 16) {
                    SetupStepView(
                        number: 1,
                        title: "Start Relay Server",
                        description: "Run 'cd relay-server && npm run dev' on your Mac"
                    )
                    SetupStepView(
                        number: 2,
                        title: "Scan QR Code",
                        description: "Open <your-mac>:3578/pair in your browser"
                    )
                    SetupStepView(
                        number: 3,
                        title: "Pick a Session",
                        description: "Choose which Claude Code session to control"
                    )
                }
                .padding(.horizontal)

                Spacer()

                VStack(spacing: 16) {
                    Button(action: {
                        requestCameraPermission()
                    }) {
                        HStack {
                            Image(systemName: "qrcode.viewfinder")
                            Text("Scan QR Code")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.blue)
                        .cornerRadius(25)
                    }

                    Button("Manual Setup") {
                        showingManualSetup = true
                    }
                    .foregroundColor(.blue)
                }
                .padding(.horizontal)
                .padding(.bottom, 50)
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $isShowingQRScanner) {
            QRScannerView { result in
                handleQRScanResult(result)
            }
        }
        .sheet(isPresented: $showingManualSetup) {
            ManualSetupView()
        }
        .onAppear {
            checkCameraPermission()
        }
    }

    private func checkCameraPermission() {
        hasPermission = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    private func requestCameraPermission() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                hasPermission = granted
                if granted {
                    isShowingQRScanner = true
                }
            }
        }
    }

    private func handleQRScanResult(_ result: String) {
        isShowingQRScanner = false

        guard let data = result.data(using: .utf8) else { return }
        do {
            let payload = try JSONDecoder().decode(QRPayload.self, from: data)
            let profile = payload.toConnectionProfile()
            appState.setupConnection(with: profile)
        } catch {
            Logger.relay.error("Invalid QR code: \(error)")
        }
    }
}

struct SetupStepView: View {
    let number: Int
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text("\(number)")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Color.blue)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }
}
