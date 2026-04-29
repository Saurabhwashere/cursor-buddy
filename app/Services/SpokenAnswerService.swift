import AVFoundation
import Foundation

@MainActor
final class SpokenAnswerService: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ response: ScreenAnalysisResponse) {
        let text = spokenText(for: response)
        guard !text.isEmpty else {
            return
        }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        utterance.pitchMultiplier = 1.0
        utterance.volume = 0.95
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func spokenText(for response: ScreenAnalysisResponse) -> String {
        if let firstStep = response.steps.first {
            return firstStep
        }

        return response.answer
    }
}
