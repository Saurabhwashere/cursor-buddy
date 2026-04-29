import Foundation

enum CodexBridgeError: LocalizedError {
    case bridgeUnavailable
    case taskFailed(String)

    var errorDescription: String? {
        switch self {
        case .bridgeUnavailable:
            return "Codex Bridge is not running. Start it with ./scripts/run-bridge.sh, then try again."
        case let .taskFailed(message):
            return message
        }
    }
}

struct CodexBridgeClient {
    private let endpoint: URL
    private let session: URLSession

    init(
        endpoint: URL = URL(string: ProcessInfo.processInfo.environment["CODEX_CURSOR_BRIDGE_URL"] ?? "http://127.0.0.1:8765/codex-task")!,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.session = session
    }

    func makeRepeatable(
        instruction: String,
        prompt: String,
        response: ScreenAnalysisResponse?,
        screenshot: CapturedScreenshot?
    ) async throws -> CodexBridgeResult {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 360

        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "instruction": instruction,
            "prompt": prompt,
            "answer": response?.answer ?? "",
            "steps": response?.steps ?? [],
            "riskWarnings": response?.riskWarnings ?? [],
            "screenshotPath": screenshot?.fileURL.path ?? "",
            "screen": [
                "capturedWidth": screenshot?.width ?? 0,
                "capturedHeight": screenshot?.height ?? 0,
                "originalWidth": screenshot?.originalWidth ?? 0,
                "originalHeight": screenshot?.originalHeight ?? 0
            ]
        ])

        do {
            let (data, urlResponse) = try await session.data(for: request)
            if let httpResponse = urlResponse as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                throw CodexBridgeError.taskFailed("Codex Bridge returned HTTP \(httpResponse.statusCode).")
            }

            let result = try JSONDecoder().decode(CodexBridgeResult.self, from: data)
            if result.ok {
                return result
            }

            throw CodexBridgeError.taskFailed(result.error ?? "Codex Bridge task failed.")
        } catch let error as CodexBridgeError {
            throw error
        } catch {
            throw CodexBridgeError.bridgeUnavailable
        }
    }
}
