import AVFoundation
import Foundation

enum SpokenAnswerProvider {
    case realtime
    case openAI
    case system

    init(environmentValue: String?) {
        switch environmentValue?.lowercased() {
        case "system", "macos", "apple":
            self = .system
        case "tts", "speech":
            self = .openAI
        default:
            self = .realtime
        }
    }
}

@MainActor
final class SpokenAnswerService: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let provider: SpokenAnswerProvider
    private let realtimeClient: RealtimeSpeechClient
    private let openAIClient: OpenAITTSClient
    private var audioPlayer: AVAudioPlayer?
    private var activeSpeechTask: Task<Void, Never>?

    override init() {
        provider = SpokenAnswerProvider(
            environmentValue: ProcessInfo.processInfo.environment["CODEX_CURSOR_TTS_PROVIDER"]
        )
        realtimeClient = RealtimeSpeechClient()
        openAIClient = OpenAITTSClient()
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ response: ScreenAnalysisResponse) {
        let text = spokenText(for: response)
        guard !text.isEmpty else {
            return
        }

        stop()

        activeSpeechTask = Task { [weak self] in
            guard let self else {
                return
            }

            switch provider {
            case .realtime:
                do {
                    let audioURL = try await realtimeClient.createSpeechAudio(
                        text: text,
                        instructions: Self.agentVoiceInstructions
                    )
                    playOpenAIAudio(at: audioURL)
                } catch {
                    await speakWithOpenAITTSOrSystem(text)
                }
            case .openAI:
                await speakWithOpenAITTSOrSystem(text)
            case .system:
                speakWithSystemVoice(text)
            }
        }
    }

    func stop() {
        activeSpeechTask?.cancel()
        activeSpeechTask = nil

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        audioPlayer?.stop()
        audioPlayer = nil
    }

    private func playOpenAIAudio(at url: URL) {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            player.play()
            audioPlayer = player
        } catch {
            speakWithSystemVoice("I found an answer, but I could not play the generated voice.")
        }
    }

    private func speakWithOpenAITTSOrSystem(_ text: String) async {
        do {
            let audioURL = try await openAIClient.createSpeechAudio(
                text: text,
                instructions: Self.agentVoiceInstructions
            )
            playOpenAIAudio(at: audioURL)
        } catch {
            speakWithSystemVoice(text)
        }
    }

    private func speakWithSystemVoice(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.88
        utterance.pitchMultiplier = 1.02
        utterance.volume = 0.95

        if let voice = AVSpeechSynthesisVoice(language: "en-AU")
            ?? AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = voice
        }

        synthesizer.speak(utterance)
    }

    private func spokenText(for response: ScreenAnalysisResponse) -> String {
        let firstStep = response.steps.first
        let base = firstStep?.isEmpty == false ? firstStep! : response.answer

        guard !base.isEmpty else {
            return ""
        }

        if response.riskWarnings.isEmpty {
            return base
        }

        return "\(base) Quick note: \(response.riskWarnings[0])"
    }

    private static let agentVoiceInstructions = """
    You are Codex Cursor, a calm screen guide helping someone use software.
    Speak naturally, warmly, and briefly, like a patient expert sitting beside the user.
    Use a friendly Australian-neutral tone. Do not sound like a phone tree.
    Keep the delivery conversational and confident. Slightly soften warnings, but keep them clear.
    """
}

private struct RealtimeSpeechClient {
    private let apiKey: String?
    private let model: String
    private let voice: String
    private let session: URLSession

    init(
        apiKey: String? = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
        model: String = ProcessInfo.processInfo.environment["OPENAI_REALTIME_MODEL"] ?? "gpt-realtime-1.5",
        voice: String = ProcessInfo.processInfo.environment["OPENAI_REALTIME_VOICE"] ?? "marin",
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.model = model
        self.voice = voice
        self.session = session
    }

    func createSpeechAudio(text: String, instructions: String) async throws -> URL {
        guard let apiKey, !apiKey.isEmpty else {
            throw URLError(.userAuthenticationRequired)
        }

        var components = URLComponents(string: "wss://api.openai.com/v1/realtime")!
        components.queryItems = [URLQueryItem(name: "model", value: model)]
        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let socket = session.webSocketTask(with: request)
        socket.resume()
        defer {
            socket.cancel(with: .normalClosure, reason: nil)
        }

        try await sendJSON([
            "type": "session.update",
            "session": [
                "type": "realtime",
                "model": model,
                "output_modalities": ["audio"],
                "audio": [
                    "output": [
                        "voice": voice,
                        "format": [
                            "type": "audio/pcm",
                            "rate": 24000
                        ]
                    ]
                ],
                "instructions": instructions
            ]
        ], socket: socket)

        try await sendJSON([
            "type": "response.create",
            "response": [
                "output_modalities": ["audio"],
                "instructions": """
                \(instructions)

                Say this exact guidance in one natural sentence or two:
                \(text)
                """
            ]
        ], socket: socket)

        var pcmData = Data()
        while true {
            let message = try await socket.receive()
            guard case let .string(jsonString) = message,
                  let data = jsonString.data(using: .utf8),
                  let event = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = event["type"] as? String else {
                continue
            }

            if type == "error" {
                throw URLError(.badServerResponse)
            }

            if (type == "response.output_audio.delta" || type == "response.audio.delta"),
               let delta = event["delta"] as? String,
               let audioChunk = Data(base64Encoded: delta) {
                pcmData.append(audioChunk)
            }

            if type == "response.done" || type == "response.output_audio.done" {
                break
            }
        }

        guard !pcmData.isEmpty else {
            throw URLError(.zeroByteResource)
        }

        let wavData = WAVFileBuilder.wrapPCM16Mono(pcmData, sampleRate: 24000)
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-cursor-realtime-\(UUID().uuidString).wav")
        try wavData.write(to: audioURL, options: [.atomic])
        return audioURL
    }

    private func sendJSON(_ object: [String: Any], socket: URLSessionWebSocketTask) async throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let text = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }

        try await socket.send(.string(text))
    }
}

private enum WAVFileBuilder {
    static func wrapPCM16Mono(_ pcmData: Data, sampleRate: Int) -> Data {
        var data = Data()
        let byteRate = sampleRate * 2
        let blockAlign = 2
        let bitsPerSample = 16
        let dataSize = UInt32(pcmData.count)
        let riffSize = UInt32(36 + pcmData.count)

        data.appendASCII("RIFF")
        data.appendLittleEndian(riffSize)
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt32(sampleRate))
        data.appendLittleEndian(UInt32(byteRate))
        data.appendLittleEndian(UInt16(blockAlign))
        data.appendLittleEndian(UInt16(bitsPerSample))
        data.appendASCII("data")
        data.appendLittleEndian(dataSize)
        data.append(pcmData)
        return data
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(string.data(using: .ascii)!)
    }

    mutating func appendLittleEndian(_ value: UInt16) {
        var littleEndian = value.littleEndian
        append(Data(bytes: &littleEndian, count: MemoryLayout<UInt16>.size))
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        var littleEndian = value.littleEndian
        append(Data(bytes: &littleEndian, count: MemoryLayout<UInt32>.size))
    }
}

private struct OpenAITTSClient {
    private let apiKey: String?
    private let model: String
    private let voice: String
    private let endpoint = URL(string: "https://api.openai.com/v1/audio/speech")!
    private let session: URLSession

    init(
        apiKey: String? = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
        model: String = ProcessInfo.processInfo.environment["OPENAI_TTS_MODEL"] ?? "gpt-4o-mini-tts",
        voice: String = ProcessInfo.processInfo.environment["OPENAI_TTS_VOICE"] ?? "marin",
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.model = model
        self.voice = voice
        self.session = session
    }

    func createSpeechAudio(text: String, instructions: String) async throws -> URL {
        guard let apiKey, !apiKey.isEmpty else {
            throw URLError(.userAuthenticationRequired)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "voice": voice,
            "input": text,
            "instructions": instructions,
            "response_format": "mp3"
        ])

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }

        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-cursor-tts-\(UUID().uuidString).mp3")
        try data.write(to: audioURL, options: [.atomic])
        return audioURL
    }
}
