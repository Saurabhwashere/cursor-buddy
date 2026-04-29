import Foundation

enum CodexClientError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case badStatus(Int, String)
    case missingOutputText

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Set OPENAI_API_KEY in the app environment before asking for a real screen analysis."
        case .invalidURL:
            return "The model endpoint URL is invalid."
        case let .badStatus(status, body):
            return "The model request failed with HTTP \(status): \(body)"
        case .missingOutputText:
            return "The model response did not include text output."
        }
    }
}

struct CodexClient {
    private let apiKey: String?
    private let model: String
    private let session: URLSession
    private let endpoint = "https://api.openai.com/v1/responses"

    init(
        apiKey: String? = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
        model: String = ProcessInfo.processInfo.environment["OPENAI_MODEL"] ?? "gpt-5.4-nano",
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    func analyzeScreen(
        prompt: String,
        mode: GuidanceMode,
        screenshot: CapturedScreenshot,
        recentContext: String
    ) async throws -> ScreenAnalysisResponse {
        guard let apiKey, !apiKey.isEmpty else {
            throw CodexClientError.missingAPIKey
        }

        guard let url = URL(string: endpoint) else {
            throw CodexClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(
            prompt: prompt,
            mode: mode,
            screenshot: screenshot,
            recentContext: recentContext
        ))

        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "No response body."
            throw CodexClientError.badStatus(httpResponse.statusCode, body)
        }

        let text = try extractOutputText(from: data)
        return try decodeScreenAnalysis(from: text)
    }

    private func requestBody(
        prompt: String,
        mode: GuidanceMode,
        screenshot: CapturedScreenshot,
        recentContext: String
    ) -> [String: Any] {
        let base64Image = screenshot.imageData.base64EncodedString()
        let contextText = recentContext.isEmpty ? "No previous turns in this session." : recentContext

        return [
            "model": model,
            "instructions": Self.systemPrompt,
            "input": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "input_text",
                            "text": """
                            Mode: \(mode.title)
                            Mode instruction: \(mode.modeInstruction)
                            Recent session context:
                            \(contextText)

                            User question: \(prompt)

                            Screenshot dimensions: \(screenshot.width)x\(screenshot.height) pixels.
                            Original display capture dimensions before compression: \(screenshot.originalWidth)x\(screenshot.originalHeight) pixels.
                            Return only the requested JSON object.
                            """
                        ],
                        [
                            "type": "input_image",
                            "image_url": "data:\(screenshot.mimeType);base64,\(base64Image)",
                            "detail": "low"
                        ]
                    ]
                ]
            ]
        ]
    }

    private func extractOutputText(from data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw CodexClientError.missingOutputText
        }

        if let outputText = dictionary["output_text"] as? String,
           !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return outputText
        }

        if let output = dictionary["output"] as? [[String: Any]] {
            for item in output {
                guard let content = item["content"] as? [[String: Any]] else {
                    continue
                }

                for contentItem in content {
                    if let text = contentItem["text"] as? String,
                       !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return text
                    }
                }
            }
        }

        throw CodexClientError.missingOutputText
    }

    private func decodeScreenAnalysis(from text: String) throws -> ScreenAnalysisResponse {
        let cleanedText = stripMarkdownFence(from: text)

        if let response = tryDecodeScreenAnalysis(cleanedText) {
            return sanitize(response)
        }

        if let jsonObject = extractJSONObject(from: cleanedText),
           let response = tryDecodeScreenAnalysis(jsonObject) {
            return sanitize(response)
        }

        return sanitize(ScreenAnalysisResponse(
            answer: cleanedText,
            steps: [],
            points: [],
            riskWarnings: ["The model response was not valid JSON, so Codex Cursor is showing it as plain text."]
        ))
    }

    private func tryDecodeScreenAnalysis(_ text: String) -> ScreenAnalysisResponse? {
        guard let data = text.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(ScreenAnalysisResponse.self, from: data)
    }

    private func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start < end else {
            return nil
        }

        return String(text[start...end])
    }

    private func stripMarkdownFence(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.hasPrefix("```") else {
            return trimmed
        }

        let lines = trimmed.components(separatedBy: .newlines)
        guard lines.count >= 3 else {
            return trimmed
        }

        return lines
            .dropFirst()
            .dropLast()
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitize(_ response: ScreenAnalysisResponse) -> ScreenAnalysisResponse {
        let sanitizedAnswer = sanitizeSensitiveInstructions(response.answer)
        let sanitizedSteps = response.steps.map(sanitizeSensitiveInstructions)
        let sanitizedWarnings = response.riskWarnings.map(sanitizeSensitiveInstructions)

        return ScreenAnalysisResponse(
            answer: sanitizedAnswer,
            steps: sanitizedSteps,
            points: response.points,
            riskWarnings: sanitizedWarnings,
            checklist: response.checklist.map { checklist in
                Checklist(
                    title: sanitizeSensitiveInstructions(checklist.title),
                    items: checklist.items.map(sanitizeSensitiveInstructions)
                )
            }
        )
    }

    private func sanitizeSensitiveInstructions(_ text: String) -> String {
        let replacements = [
            "enter your credentials (such as your username and password)": "continue through the official login flow",
            "enter your email address, mobile number, or mygov username": "use the official login page's requested identifier field",
            "enter a valid email address, mobile number, or mygov username": "Use the official login page's requested identifier field",
            "enter your valid email address, mobile number, or mygov username": "Use the official login page's requested identifier field",
            "enter your email, mobile number, or mygov username": "use the official login page's requested identifier field",
            "enter your email address": "use the official login page's requested identifier field",
            "enter your username": "use the official login page's requested identifier field",
            "enter your username/email and password": "continue through the official login flow",
            "enter your username or email and password": "continue through the official login flow",
            "enter your login credentials": "continue through the official login flow",
            "entering your login details": "continuing through the official login flow",
            "enter your login details": "continue through the official login flow",
            "enter your credentials": "continue through the official login flow",
            "enter your password": "continue through the official login flow",
            "type your password": "continue through the official login flow",
            "type your code": "continue through the official login flow",
            "one-time code": "security code"
        ]

        var sanitized = text
        for (target, replacement) in replacements {
            sanitized = sanitized.replacingOccurrences(
                of: target,
                with: replacement,
                options: [.caseInsensitive]
            )
        }

        return sanitized
    }

    private static let systemPrompt = """
    You are Codex Cursor, a screen-aware assistant.

    The product lives beside the user's cursor. The user presses Option, asks a short question, follows your guidance, then presses Option again for the next step.

    Given a screenshot, recent session context, and the user's question:
    1. Explain only what matters right now in plain English.
    2. Give one immediate next action by default. Use one short sentence where possible. Use up to 2 short steps only if the user asks for a broader explanation.
    3. If there is a visible target to click or inspect, identify one screen location to point at.
    4. Preserve continuity with the recent session context, especially when the user says "I did that", "what now", or similar.

    Return JSON:
    {
      "answer": string,
      "steps": string[],
      "points": [
        { "x": number, "y": number, "label": string }
      ],
      "riskWarnings": string[],
      "checklist": {
        "title": string,
        "items": string[]
      } | null
    }

    Coordinates must be pixel coordinates relative to the screenshot. Put each point at the visual center of the actual clickable or editable UI element, not on nearby text, labels, headings, divider lines, or explanatory copy. For text fields, point at the center of the input rectangle. For buttons, point at the center of the button.
    For checklist mode, checklist must contain a title and useful checklist items. For other modes, checklist can be null.
    If you are unsure, return an empty points array.
    Do not ask the user to share sensitive information with you, including passwords, credentials, payment details, private keys, payment card numbers, or one-time codes.
    For login screens, you may tell the user to use the official login form themselves, but do not ask them to tell you secret values. Add a short risk warning reminding them to keep passwords and codes private when relevant.
    If the screen appears to involve high-stakes financial, legal, medical, or government decisions, explain carefully and recommend verifying with an official source or qualified person.
    Return only valid JSON with no Markdown.
    """
}
