import AppKit
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var prompt = "What do I do next?"
    @Published var selectedMode: GuidanceMode = .nextStep
    @Published var latestScreenshot: CapturedScreenshot?
    @Published var latestResponse: ScreenAnalysisResponse?
    @Published var isLoading = false
    @Published var isListening = false
    @Published var isPointerOverlayVisible = false
    @Published var canShowPointerOverlay = false
    @Published var pendingArtifact: GeneratedArtifact?
    @Published var errorMessage: String?
    @Published var summonHint = "Press Option to ask Codex Cursor about the current screen."

    private let screenshotService: ScreenshotService
    private let codexClient: CodexClient
    private let overlayController: OverlayController
    private let cursorCompanionController: CursorCompanionController
    private let voiceInputService: VoiceInputService
    private let spokenAnswerService: SpokenAnswerService
    private let artifactService: ArtifactService
    private var hotkeyMonitor: HotkeyMonitor?
    private var pointerVisibilityTask: Task<Void, Never>?
    private var speakingStateTask: Task<Void, Never>?
    private var recentTurns: [String] = []

    init(
        screenshotService: ScreenshotService = ScreenshotService(),
        codexClient: CodexClient = CodexClient(),
        artifactService: ArtifactService = ArtifactService(),
        overlayController: OverlayController? = nil,
        cursorCompanionController: CursorCompanionController? = nil,
        voiceInputService: VoiceInputService = VoiceInputService(),
        spokenAnswerService: SpokenAnswerService? = nil
    ) {
        self.screenshotService = screenshotService
        self.codexClient = codexClient
        self.artifactService = artifactService
        self.overlayController = overlayController ?? OverlayController()
        self.cursorCompanionController = cursorCompanionController ?? CursorCompanionController()
        self.voiceInputService = voiceInputService
        self.spokenAnswerService = spokenAnswerService ?? SpokenAnswerService()
    }

    func startHotkeyMonitoring() {
        guard hotkeyMonitor == nil else {
            return
        }

        let monitor = HotkeyMonitor(
            onOptionDown: { [weak self] in
                self?.startPushToTalk()
            },
            onOptionUp: { [weak self] in
                self?.finishPushToTalk()
            }
        )
        hotkeyMonitor = monitor
        monitor.start()
        cursorCompanionController.start()
    }

    func summonBesideCursor() {
        summonHint = "Ask one question. Codex will look at this screen and give the next step."
        cursorCompanionController.showLabel(status: "Ask me")

        if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prompt = "What do I do next?"
        }

        NSApp.activate(ignoringOtherApps: true)

        guard let window = NSApp.windows.first(where: { $0.title == "Codex Cursor" }) ?? NSApp.windows.first else {
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        let targetSize = CGSize(width: 520, height: 560)
        let visibleFrame = NSScreen.screens
            .first(where: { $0.frame.contains(mouseLocation) })?
            .visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        let targetOrigin = clampedPanelOrigin(
            near: mouseLocation,
            size: targetSize,
            visibleFrame: visibleFrame
        )

        window.setFrame(
            CGRect(origin: targetOrigin, size: targetSize),
            display: true,
            animate: true
        )
        window.makeKeyAndOrderFront(nil)
    }

    func startPushToTalk() {
        guard !isListening, !isLoading else {
            return
        }

        isListening = true
        errorMessage = nil
        spokenAnswerService.stop()
        speakingStateTask?.cancel()
        speakingStateTask = nil
        prompt = ""
        summonHint = "Listening. Release Option to ask Codex about this screen."
        cursorCompanionController.showAnswer(
            title: "Listening",
            text: "Speak now. Release Option when you're done.",
            activity: .listening,
            collapseAfter: nil
        )

        Task {
            do {
                try await voiceInputService.start { [weak self] transcript in
                    self?.prompt = transcript
                    self?.cursorCompanionController.showAnswer(
                        title: "Listening",
                        text: transcript.isEmpty ? "Speak now. Release Option when you're done." : transcript,
                        activity: .listening,
                        collapseAfter: nil
                    )
                }
            } catch {
                isListening = false
                cursorCompanionController.showAnswer(
                    title: "Mic setup",
                    text: AppState.userFacingMessage(for: error),
                    collapseAfter: 8
                )
                errorMessage = AppState.userFacingMessage(for: error)
            }
        }
    }

    func finishPushToTalk() {
        guard isListening else {
            return
        }

        isListening = false
        let transcript = voiceInputService.stop()
        let spokenPrompt = transcript.isEmpty ? prompt.trimmingCharacters(in: .whitespacesAndNewlines) : transcript

        guard !spokenPrompt.isEmpty else {
            prompt = "What do I do next?"
            summonHint = "I did not catch that. Hold Option and try again."
            cursorCompanionController.showAnswer(
                title: "Try again",
                text: "I did not catch that. Hold Option and ask once more.",
                collapseAfter: 5
            )
            return
        }

        prompt = spokenPrompt
        summonHint = "Got it. Codex is looking at the current screen."
        cursorCompanionController.showAnswer(
            title: "Got it",
            text: spokenPrompt,
            activity: .thinking,
            collapseAfter: nil
        )

        Task {
            await captureAndAnalyze(speakAnswer: true)
        }
    }

    func captureAndAnalyze(speakAnswer: Bool = false) async {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            errorMessage = "Enter a question before analyzing the screen."
            return
        }

        isLoading = true
        errorMessage = nil
        cursorCompanionController.showAnswer(
            title: "Looking",
            text: "Checking the current screen...",
            activity: .thinking,
            collapseAfter: nil
        )
        var hiddenCompanionWindow: NSWindow?

        do {
            hiddenCompanionWindow = hideCompanionWindowForScreenshot()
            cursorCompanionController.hideForScreenshot()
            try? await Task.sleep(nanoseconds: 160_000_000)
            let screenshot = try screenshotService.captureFullScreen()
            latestScreenshot = screenshot
            restoreCompanionWindowAfterScreenshot(hiddenCompanionWindow)
            hiddenCompanionWindow = nil
            cursorCompanionController.showAfterScreenshot()
            cursorCompanionController.showAnswer(
                title: "Thinking",
                text: "Working out the next step...",
                activity: .thinking,
                collapseAfter: nil
            )

            let response = try await codexClient.analyzeScreen(
                prompt: trimmedPrompt,
                mode: selectedMode,
                screenshot: screenshot,
                recentContext: recentTurns.suffix(4).joined(separator: "\n\n")
            )
            latestResponse = response
            rememberTurn(question: trimmedPrompt, response: response)
            pendingArtifact = nil
            canShowPointerOverlay = false
            cursorCompanionController.showAnswer(
                title: "Next step",
                text: cursorDisplayText(for: response),
                activity: speakAnswer ? .speaking : .idle,
                collapseAfter: speakAnswer ? nil : 10
            )
            if speakAnswer {
                spokenAnswerService.speak(response)
                scheduleSpeakingStateReset()
            }
        } catch {
            restoreCompanionWindowAfterScreenshot(hiddenCompanionWindow)
            latestResponse = nil
            canShowPointerOverlay = false
            hidePointerOverlay()
            cursorCompanionController.showAfterScreenshot()
            errorMessage = AppState.userFacingMessage(for: error)
            cursorCompanionController.showAnswer(
                title: "Needs setup",
                text: AppState.userFacingMessage(for: error),
                collapseAfter: 8
            )
        }

        isLoading = false
    }

    func setDefaultNextQuestion() {
        selectedMode = .nextStep
        prompt = latestResponse == nil ? "What do I do next?" : "Okay, I did that. What do I do now?"
    }

    func hidePointerOverlay() {
        pointerVisibilityTask?.cancel()
        pointerVisibilityTask = nil
        isPointerOverlayVisible = false
    }

    func showPointerOverlayAgain() {
        canShowPointerOverlay = false
        isPointerOverlayVisible = false
    }

    func copyChecklistToClipboard() {
        guard let markdown = latestResponse?.checklistMarkdown else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }

    func exportChecklistToMarkdown() {
        guard let markdown = latestResponse?.checklistMarkdown else {
            errorMessage = "There is no checklist to export."
            return
        }

        do {
            let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("generated-tools/checklists", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let title = latestResponse?.checklist?.title ?? "Checklist"
            let filename = "\(Self.slug(title))-\(Self.timestamp()).md"
            let fileURL = directory.appendingPathComponent(filename)
            try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
            errorMessage = "Checklist exported to \(fileURL.path)"
        } catch {
            errorMessage = AppState.userFacingMessage(for: error)
        }
    }

    func createReusableGuide() {
        guard let latestResponse else {
            errorMessage = "Analyze a screen before creating a guide."
            return
        }

        pendingArtifact = artifactService.createGuide(
            prompt: prompt,
            mode: selectedMode,
            response: latestResponse
        )
        errorMessage = nil
    }

    func copyPendingArtifact() {
        guard let pendingArtifact else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pendingArtifact.markdown, forType: .string)
    }

    func savePendingArtifact() {
        guard let pendingArtifact else {
            errorMessage = "Create a guide before saving."
            return
        }

        do {
            let fileURL = try artifactService.save(pendingArtifact)
            self.pendingArtifact = nil
            errorMessage = "Guide saved to \(fileURL.path)"
        } catch {
            errorMessage = AppState.userFacingMessage(for: error)
        }
    }

    func closePendingArtifact() {
        pendingArtifact = nil
    }

    private func markPointerOverlayHidden() {
        pointerVisibilityTask = nil
        isPointerOverlayVisible = false
    }

    private func hideCompanionWindowForScreenshot() -> NSWindow? {
        let window = NSApp.windows.first(where: { $0.title == "Codex Cursor" && $0.isVisible })
        window?.orderOut(nil)
        return window
    }

    private func restoreCompanionWindowAfterScreenshot(_ window: NSWindow?) {
        guard let window else {
            return
        }

        window.makeKeyAndOrderFront(nil)
    }

    private func rememberTurn(question: String, response: ScreenAnalysisResponse) {
        let stepSummary = response.steps.first.map { "Next step: \($0)" } ?? "Answer: \(response.answer)"
        recentTurns.append("User asked: \(question)\nCodex replied: \(stepSummary)")

        if recentTurns.count > 6 {
            recentTurns.removeFirst(recentTurns.count - 6)
        }
    }

    private func cursorDisplayText(for response: ScreenAnalysisResponse) -> String {
        if let firstStep = response.steps.first,
           !firstStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return firstStep
        }

        return response.answer
    }

    private func scheduleSpeakingStateReset() {
        speakingStateTask?.cancel()
        speakingStateTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 18_000_000_000)
            self?.cursorCompanionController.showIcon(status: "Ready")
        }
    }

    private func clampedPanelOrigin(near point: NSPoint, size: CGSize, visibleFrame: CGRect) -> CGPoint {
        let preferredX = point.x + 18
        let preferredY = point.y - size.height - 18

        let x = min(
            max(preferredX, visibleFrame.minX + 12),
            visibleFrame.maxX - size.width - 12
        )
        let y = min(
            max(preferredY, visibleFrame.minY + 12),
            visibleFrame.maxY - size.height - 12
        )

        return CGPoint(x: x, y: y)
    }

    private static func userFacingMessage(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }

        return error.localizedDescription
    }

    private static func slug(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let scalars = text.lowercased().unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        return String(scalars)
            .split(separator: "-")
            .joined(separator: "-")
            .prefix(48)
            .description
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

extension ScreenAnalysisResponse {
    var checklistMarkdown: String? {
        guard let checklist else {
            return nil
        }

        let items = checklist.items
            .map { "- \($0)" }
            .joined(separator: "\n")
        return "# \(checklist.title)\n\n\(items)\n"
    }
}
