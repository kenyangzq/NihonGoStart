import Foundation
import AVFoundation

/// Shared speech manager to handle Japanese text-to-speech without blocking the main thread
@MainActor
class SpeechManager: NSObject, ObservableObject {
    static let shared = SpeechManager()

    private let synthesizer = AVSpeechSynthesizer()
    private var japaneseVoice: AVSpeechSynthesisVoice?

    @Published var isSpeaking = false

    private override init() {
        super.init()
        synthesizer.delegate = self

        // Pre-load the Japanese voice on a background thread to avoid blocking
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let voice = AVSpeechSynthesisVoice(language: "ja-JP")
            DispatchQueue.main.async {
                self?.japaneseVoice = voice
            }
        }
    }

    /// Speaks the given Japanese text
    /// - Parameters:
    ///   - text: The Japanese text to speak
    ///   - rate: Speech rate multiplier (default 0.8 for slower, clearer speech)
    func speak(_ text: String, rate: Float = 0.8) {
        // Stop any current speech
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        // Create utterance on background thread to avoid blocking
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = self.japaneseVoice ?? AVSpeechSynthesisVoice(language: "ja-JP")
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * rate

            DispatchQueue.main.async {
                self.isSpeaking = true
                self.synthesizer.speak(utterance)
            }
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
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
    }
}
