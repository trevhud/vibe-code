import SwiftUI
import AVFoundation

struct SetupView: View {
    @EnvironmentObject var appState: AppState
    @State private var isShowingQRScanner = false
    @State private var showingManualSetup = false
    @State private var showingSessionPicker = false
    @State private var hasPermission = false
    @State private var scannedPayload: ConnectionPayload?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "laptopcomputer.and.iphone")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                    
                    Text("Welcome to Vibe Code")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Continue your Claude Code conversations anywhere")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 50)
                
                Spacer()
                
                // Setup Instructions
                VStack(alignment: .leading, spacing: 16) {
                    SetupStepView(
                        number: 1,
                        title: "Install Tailscale",
                        description: "Download Tailscale from the App Store and sign in with the same account as your Mac"
                    )
                    
                    SetupStepView(
                        number: 2,
                        title: "Run Setup on Mac",
                        description: "Open Terminal and run: vibe-code setup"
                    )
                    
                    SetupStepView(
                        number: 3,
                        title: "Scan QR Code",
                        description: "Run 'vibe-code connect' on your Mac and scan the QR code"
                    )
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Action Buttons
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
                    .disabled(!hasPermission)
                    
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
        .sheet(isPresented: $showingSessionPicker) {
            if let payload = scannedPayload {
                SessionPickerView(payload: payload) { selectedSession in
                    let profile = payload.toConnectionProfile(selectedSession: selectedSession)
                    appState.setupConnection(with: profile)
                }
            }
        }
        .onAppear {
            checkCameraPermission()
        }
    }
    
    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            hasPermission = true
        case .notDetermined:
            hasPermission = false
        case .denied, .restricted:
            hasPermission = false
        @unknown default:
            hasPermission = false
        }
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
        do {
            let data = result.data(using: .utf8)!
            let payload = try JSONDecoder().decode(ConnectionPayload.self, from: data)
            
            isShowingQRScanner = false
            
            if payload.hasMultipleSessions {
                // Show session picker
                scannedPayload = payload
                showingSessionPicker = true
            } else {
                // Connect directly to the single session
                let profile = payload.toConnectionProfile()
                appState.setupConnection(with: profile)
            }
        } catch {
            // Handle invalid QR code
            print("Invalid QR code: \(error)")
            isShowingQRScanner = false
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

#Preview {
    SetupView()
        .environmentObject(AppState())
}