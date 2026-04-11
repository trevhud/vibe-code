import AVFoundation
import Combine

@MainActor
class AppleTTSProvider: NSObject, ObservableObject {
    @Published private(set) var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Never>?
    private var selectedVoice: AVSpeechSynthesisVoice?

    override init() {
        super.init()
        synthesizer.delegate = self
        selectedVoice = Self.bestAvailableVoice()
    }

    func speak(_ text: String) async {
        if synthesizer.isSpeaking {
            stopAndCancelContinuation()
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.5
        utterance.voice = selectedVoice

        isSpeaking = true

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.continuation = cont
            self.synthesizer.speak(utterance)
        }

        isSpeaking = false
    }

    func stop() {
        stopAndCancelContinuation()
        isSpeaking = false
    }

    private func stopAndCancelContinuation() {
        synthesizer.stopSpeaking(at: .immediate)
        if let cont = continuation {
            continuation = nil
            cont.resume()
        }
    }

    // Prefer premium > enhanced > default English voice
    private static func bestAvailableVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }

        if let premium = voices.first(where: { $0.quality == .premium }) {
            return premium
        }
        if let enhanced = voices.first(where: { $0.quality == .enhanced }) {
            return enhanced
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }
}

extension AppleTTSProvider: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            if let cont = self.continuation {
                self.continuation = nil
                cont.resume()
            }
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            if let cont = self.continuation {
                self.continuation = nil
                cont.resume()
            }
        }
    }
}
