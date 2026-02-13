import Foundation
import AVFoundation

/// Shared speech manager to handle Japanese text-to-speech without blocking the main thread
@MainActor
class SpeechManager: NSObject, ObservableObject, @unchecked Sendable {
    static let shared = SpeechManager()

    private let synthesizer = AVSpeechSynthesizer()
    private var japaneseVoice: AVSpeechSynthesisVoice?

    @Published var isSpeaking = false

    private override init() {
        super.init()
        synthesizer.delegate = self

        // Pre-load the Japanese voice
        let voice = AVSpeechSynthesisVoice(language: "ja-JP")
        self.japaneseVoice = voice
    }

    /// Speaks the given Japanese text
    /// - Parameters:
    ///   - text: The Japanese text to speak
    ///   - rate: Speech rate multiplier (default 0.8 for slower, clearer speech)
    nonisolated func speak(_ text: String, rate: Float = 0.8) {
        // Stop any current speech
        Task { @MainActor in
            if self.synthesizer.isSpeaking {
                self.synthesizer.stopSpeaking(at: .immediate)
            }

            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = self.japaneseVoice ?? AVSpeechSynthesisVoice(language: "ja-JP")
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * rate

            self.isSpeaking = true
            self.synthesizer.speak(utterance)
        }
    }

    /// Stops any current speech
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension SpeechManager: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }
}
