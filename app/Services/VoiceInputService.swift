import AVFoundation
import AudioTapSupport
import Foundation
import Speech

enum VoiceInputError: LocalizedError {
    case speechPermissionDenied
    case microphonePermissionDenied
    case recognizerUnavailable
    case audioInputUnavailable
    case audioTapFailed(String)

    var errorDescription: String? {
        switch self {
        case .speechPermissionDenied:
            return "Speech recognition permission is required. Enable it in System Settings, then relaunch AI Cursor Buddy."
        case .microphonePermissionDenied:
            return "Microphone permission is required to use push-to-talk."
        case .recognizerUnavailable:
            return "Speech recognition is not currently available."
        case .audioInputUnavailable:
            return "No microphone input is available."
        case let .audioTapFailed(message):
            return "Could not start microphone capture: \(message)"
        }
    }
}

final class VoiceInputService {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var latestTranscript = ""

    func start(onTranscript: @escaping @MainActor (String) -> Void) async throws {
        try await requestPermissions()

        guard let recognizer, recognizer.isAvailable else {
            throw VoiceInputError.recognizerUnavailable
        }

        stop()
        latestTranscript = ""

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.channelCount > 0 else {
            throw VoiceInputError.audioInputUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let result {
                self?.latestTranscript = result.bestTranscription.formattedString
                let transcript = result.bestTranscription.formattedString
                Task { @MainActor in
                    onTranscript(transcript)
                }
            }

            if error != nil || result?.isFinal == true {
                self?.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                self?.recognitionRequest = nil
                self?.recognitionTask = nil
            }
        }

        inputNode.removeTap(onBus: 0)
        do {
            try installInputTap(on: inputNode, format: format)
        } catch {
            recognitionRequest = nil
            recognitionTask?.cancel()
            recognitionTask = nil
            throw error
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    @discardableResult
    func stop() -> String {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        recognitionRequest?.endAudio()
        recognitionTask?.finish()
        recognitionRequest = nil
        recognitionTask = nil
        return latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func requestPermissions() async throws {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard speechStatus == .authorized else {
            throw VoiceInputError.speechPermissionDenied
        }

        let microphoneGranted = await AVCaptureDevice.requestAccess(for: .audio)
        guard microphoneGranted else {
            throw VoiceInputError.microphonePermissionDenied
        }
    }

    private func installInputTap(on inputNode: AVAudioInputNode, format: AVAudioFormat) throws {
        do {
            try AudioTapInstaller.installTap(
                on: inputNode,
                bufferSize: 1024,
                format: format
            ) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }
            return
        } catch {
            inputNode.removeTap(onBus: 0)
        }

        do {
            try AudioTapInstaller.installTap(
                on: inputNode,
                bufferSize: 1024,
                format: nil
            ) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }
        } catch {
            throw VoiceInputError.audioTapFailed(error.localizedDescription)
        }
    }
}
