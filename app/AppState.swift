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
    @Published var latestCodexBridgeResult: CodexBridgeResult?
    @Published var isCodexTaskRunning = false
    @Published var errorMessage: String?
    @Published var summonHint = "Press Option to ask Codex Cursor about the current screen."
    @Published var permissionStatuses: [PermissionStatus] = []
    @Published var pendingCodexActionOffer: String?

    private let screenshotService: ScreenshotService
    private let permissionStatusService: PermissionStatusService
    private let codexClient: CodexClient
    private let codexBridgeClient: CodexBridgeClient
    private let overlayController: OverlayController
    private let cursorCompanionController: CursorCompanionController
    private let voiceInputService: VoiceInputService
    private let spokenAnswerService: SpokenAnswerService
    private let artifactService: ArtifactService
    private let memoryStore: InteractionMemoryStore
    private let actionRouter: ActionRouter
    private var hotkeyMonitor: HotkeyMonitor?
    private var pointerVisibilityTask: Task<Void, Never>?
    private var speakingStateTask: Task<Void, Never>?
    private var recentTurns: [String] = []
    private var pendingCodexActionPrompt: String?
    private var pendingGuidancePrompt: String?

    init(
        screenshotService: ScreenshotService = ScreenshotService(),
        permissionStatusService: PermissionStatusService = PermissionStatusService(),
        codexClient: CodexClient = CodexClient(),
        codexBridgeClient: CodexBridgeClient = CodexBridgeClient(),
        artifactService: ArtifactService = ArtifactService(),
        overlayController: OverlayController? = nil,
        cursorCompanionController: CursorCompanionController? = nil,
        voiceInputService: VoiceInputService = VoiceInputService(),
        spokenAnswerService: SpokenAnswerService? = nil,
        memoryStore: InteractionMemoryStore = InteractionMemoryStore(),
        actionRouter: ActionRouter = ActionRouter()
    ) {
        self.screenshotService = screenshotService
        self.permissionStatusService = permissionStatusService
        self.codexClient = codexClient
        self.codexBridgeClient = codexBridgeClient
        self.artifactService = artifactService
        self.overlayController = overlayController ?? OverlayController()
        self.cursorCompanionController = cursorCompanionController ?? CursorCompanionController()
        self.voiceInputService = voiceInputService
        self.spokenAnswerService = spokenAnswerService ?? SpokenAnswerService()
        self.memoryStore = memoryStore
        self.actionRouter = actionRouter
        refreshPermissionStatuses()
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
        refreshPermissionStatuses()
    }

    func refreshPermissionStatuses() {
        permissionStatuses = permissionStatusService.currentStatuses()
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
                refreshPermissionStatuses()
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

        Task {
            await handleSpokenPrompt(spokenPrompt)
        }
    }

    private func handleSpokenPrompt(_ spokenPrompt: String) async {
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

        let route = actionRouter.route(
            spokenPrompt,
            context: RouterContext(hasPendingCodexOffer: pendingCodexActionPrompt != nil)
        )

        switch route {
        case .memoryFollowUp:
            if await handleMemoryFollowUp(spokenPrompt) {
                return
            }
            clearPendingCodexOffer()
            await captureAndAnalyze(speakAnswer: true)
        case .acceptCodexOffer:
            guard let pendingCodexActionPrompt else {
                clearPendingCodexOffer()
                await captureAndAnalyze(speakAnswer: true)
                return
            }
            prompt = pendingCodexActionPrompt
            clearPendingCodexOffer()
            await runCurrentPromptWithCodex(captureFreshScreen: true)
        case .declineCodexOffer:
            guard let pendingGuidancePrompt else {
                clearPendingCodexOffer()
                await captureAndAnalyze(speakAnswer: true)
                return
            }
            prompt = pendingGuidancePrompt
            clearPendingCodexOffer()
            await captureAndAnalyze(speakAnswer: true)
        case .macAction, .codexAction:
            clearPendingCodexOffer()
            await runCurrentPromptWithCodex(captureFreshScreen: true)
        case .offerAutomation:
            offerCodexAutomation(for: spokenPrompt)
        case .riskCheck:
            selectedMode = .riskCheck
            clearPendingCodexOffer()
            await captureAndAnalyze(speakAnswer: true)
        case let .clarify(question):
            showMemoryAnswer(question)
        case .screenGuidance:
            clearPendingCodexOffer()
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
                recentContext: combinedRecentContext()
            )
            latestResponse = response
            rememberTurn(question: trimmedPrompt, response: response)
            memoryStore.append(InteractionMemoryEntry(
                userText: trimmedPrompt,
                intent: .screenGuidance,
                status: .answered,
                assistantText: cursorDisplayText(for: response)
            ))
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
            refreshPermissionStatuses()
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

    func makeLatestWorkflowRepeatable() {
        guard !isCodexTaskRunning else {
            return
        }

        guard latestResponse != nil || latestScreenshot != nil else {
            errorMessage = "Ask about a screen before sending work to Codex."
            return
        }

        isCodexTaskRunning = true
        latestCodexBridgeResult = nil
        errorMessage = nil
        cursorCompanionController.showAnswer(
            title: "Codex is building",
            text: "Turning this workflow into a reusable local artifact...",
            activity: .thinking,
            collapseAfter: nil
        )

        Task {
            do {
                let result = try await codexBridgeClient.makeRepeatable(
                    instruction: "Make this workflow repeatable. Create the safest useful artifact for it.",
                    prompt: prompt,
                    response: latestResponse,
                    screenshot: latestScreenshot
                )
                latestCodexBridgeResult = result
                cursorCompanionController.showAnswer(
                    title: "Codex finished",
                    text: result.finalMessage ?? "Task completed.",
                    collapseAfter: 14
                )
            } catch {
                errorMessage = AppState.userFacingMessage(for: error)
                cursorCompanionController.showAnswer(
                    title: "Bridge setup",
                    text: AppState.userFacingMessage(for: error),
                    collapseAfter: 10
                )
            }

            isCodexTaskRunning = false
        }
    }

    func runCurrentPromptWithCodex(captureFreshScreen: Bool = true) async {
        guard !isCodexTaskRunning else {
            return
        }

        if let pendingCodexActionPrompt {
            prompt = pendingCodexActionPrompt
        }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            errorMessage = "Tell Codex what action you want it to run."
            cursorCompanionController.showAnswer(
                title: "Need a task",
                text: "Tell Codex what action you want it to run.",
                collapseAfter: 6
            )
            return
        }

        isCodexTaskRunning = true
        latestCodexBridgeResult = nil
        errorMessage = nil
        summonHint = "Codex is turning your request into an action."
        let memoryEntry = memoryStore.append(InteractionMemoryEntry(
            userText: trimmedPrompt,
            intent: memoryIntent(for: trimmedPrompt),
            status: .running,
            assistantText: "Running Codex action."
        ))
        cursorCompanionController.showAnswer(
            title: "Running Codex",
            text: "I am giving Codex the current screen and your action request...",
            activity: .thinking,
            collapseAfter: nil
        )

        var screenshotForTask = latestScreenshot
        var hiddenCompanionWindow: NSWindow?

        do {
            if captureFreshScreen {
                hiddenCompanionWindow = hideCompanionWindowForScreenshot()
                cursorCompanionController.hideForScreenshot()
                try? await Task.sleep(nanoseconds: 160_000_000)
                screenshotForTask = try screenshotService.captureFullScreen()
                latestScreenshot = screenshotForTask
                restoreCompanionWindowAfterScreenshot(hiddenCompanionWindow)
                hiddenCompanionWindow = nil
                cursorCompanionController.showAfterScreenshot()
            }

            let profile = codexActionProfile(for: trimmedPrompt)
            cursorCompanionController.showAnswer(
                title: "Codex is working",
                text: progressText(forCodexProfile: profile),
                activity: .thinking,
                collapseAfter: nil
            )

            let result = try await codexBridgeClient.runAction(
                instruction: trimmedPrompt,
                prompt: trimmedPrompt,
                response: latestResponse,
                screenshot: screenshotForTask,
                profile: profile
            )

            latestCodexBridgeResult = result
            clearPendingCodexOffer()
            summonHint = "Codex finished. Check the generated workspace for the result."
            let artifactPath = artifactPath(from: result)
            memoryStore.update(
                id: memoryEntry.id,
                status: .succeeded,
                assistantText: completionText(for: result),
                artifactPath: artifactPath,
                workspacePath: result.workspace
            )
            cursorCompanionController.showAnswer(
                title: "Codex finished",
                text: result.finalMessage ?? "Codex finished the action task.",
                collapseAfter: 14
            )
            spokenAnswerService.speak(completionText(for: result))
            scheduleSpeakingStateReset()
        } catch {
            restoreCompanionWindowAfterScreenshot(hiddenCompanionWindow)
            cursorCompanionController.showAfterScreenshot()
            let message = AppState.userFacingMessage(for: error)
            errorMessage = message
            memoryStore.update(
                id: memoryEntry.id,
                status: .failed,
                assistantText: message,
                workspacePath: nil,
                errorMessage: message
            )
            cursorCompanionController.showAnswer(
                title: "Codex action",
                text: message,
                collapseAfter: 10
            )
        }

        isCodexTaskRunning = false
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

    private func combinedRecentContext() -> String {
        [
            recentTurns.suffix(4).joined(separator: "\n\n"),
            memoryStore.recentSummary(limit: 5)
        ]
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: "\n\nRecent task memory:\n")
    }

    private func handleMemoryFollowUp(_ text: String) async -> Bool {
        if shouldRetryLastAction(text), let latestAction = memoryStore.latestAction() {
            prompt = latestAction.userText
            cursorCompanionController.showAnswer(
                title: "Trying again",
                text: "I will try the last Codex action again.",
                activity: .thinking,
                collapseAfter: nil
            )
            await runCurrentPromptWithCodex(captureFreshScreen: true)
            return true
        }

        if shouldRevealLastArtifact(text) {
            if revealLatestArtifactIfPossible() {
                showMemoryAnswer("I opened the saved file in Finder.")
            } else {
                showMemoryAnswer(answerForLatestAction())
            }
            return true
        }

        if shouldAskAboutLatestAction(text) {
            showMemoryAnswer(answerForLatestAction())
            return true
        }

        return false
    }

    private func showMemoryAnswer(_ answer: String) {
        latestResponse = ScreenAnalysisResponse(
            answer: answer,
            steps: [answer],
            points: [],
            riskWarnings: []
        )
        rememberTurn(question: prompt, response: latestResponse ?? .empty)
        cursorCompanionController.showAnswer(
            title: "Memory",
            text: answer,
            activity: .speaking,
            collapseAfter: nil
        )
        spokenAnswerService.speak(answer)
        scheduleSpeakingStateReset()
    }

    private func answerForLatestAction() -> String {
        guard let latestAction = memoryStore.latestAction() else {
            return "I do not have a saved file from this session yet. Ask me to save the current page and I can try it."
        }

        switch latestAction.status {
        case .succeeded:
            if let artifactPath = latestAction.artifactPath {
                let exists = FileManager.default.fileExists(atPath: artifactPath)
                if exists {
                    return "I saved it here: \(artifactPath). If you cannot see it, open Desktop and look for \(URL(fileURLWithPath: artifactPath).lastPathComponent)."
                }

                return "I recorded that it was saved here: \(artifactPath), but I cannot find that file now. I can try saving it again."
            }

            if let workspacePath = latestAction.workspacePath {
                return "Codex finished the task in this workspace: \(workspacePath). I do not have a Desktop file path for it."
            }

            return latestAction.assistantText ?? "Codex finished the last action, but I do not have a file path for it."
        case .failed:
            let reason = latestAction.errorMessage ?? latestAction.assistantText ?? "the bridge returned an error"
            return "It was not saved yet. The last Codex attempt failed because: \(reason). You can say 'try again' and I will retry it."
        case .running:
            return "The last Codex action is still marked as running. Wait a moment, or try again if nothing changes."
        case .offered:
            return "I offered to use Codex for that, but I have not run it yet. Say 'use Codex' if you want me to do it."
        case .answered:
            return latestAction.assistantText ?? "I answered the last request, but I do not have an action result for it."
        }
    }

    private func revealLatestArtifactIfPossible() -> Bool {
        guard let artifactPath = memoryStore.latestAction()?.artifactPath,
              FileManager.default.fileExists(atPath: artifactPath) else {
            return false
        }

        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: artifactPath)])
        return true
    }

    private func shouldAskAboutLatestAction(_ text: String) -> Bool {
        actionRouter.shouldAskAboutLatestAction(text)
    }

    private func shouldRevealLastArtifact(_ text: String) -> Bool {
        actionRouter.shouldRevealLastArtifact(text)
    }

    private func shouldRetryLastAction(_ text: String) -> Bool {
        actionRouter.shouldRetryLastAction(text)
    }

    private func memoryIntent(for text: String) -> InteractionIntent {
        actionRouter.memoryIntent(for: text)
    }

    private func artifactPath(from result: CodexBridgeResult) -> String? {
        guard let finalMessage = result.finalMessage else {
            return nil
        }

        return finalMessage
            .components(separatedBy: .newlines)
            .first { $0.lowercased().hasPrefix("saved as:") }?
            .replacingOccurrences(of: "Saved as:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shouldRunWithCodex(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let codexTriggers = [
            "use codex",
            "ask codex to",
            "get codex to",
            "have codex",
            "run codex",
            "using codex",
            "with codex"
        ]

        return codexTriggers.contains { normalized.contains($0) }
    }

    private func shouldOfferCodexAutomation(_ text: String) -> Bool {
        isHelpIntent(text) && isBrowserSaveToDesktopIntent(text)
    }

    private func shouldDelegateBrowserSave(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let delegatePhrases = [
            "can you",
            "could you",
            "please",
            "do it",
            "for me",
            "go ahead"
        ]

        return isBrowserSaveToDesktopIntent(text)
            && delegatePhrases.contains { normalized.contains($0) }
            && !isHelpIntent(text)
    }

    private func shouldDelegateScreenshot(_ text: String) -> Bool {
        isScreenshotIntent(text) && !isHelpIntent(text)
    }

    private func shouldDelegateDirectAction(_ text: String) -> Bool {
        shouldDelegateBrowserSave(text)
            || shouldDelegateScreenshot(text)
            || isCopyURLIntent(text)
            || isPageMarkdownIntent(text)
            || isCreateDesktopFolderIntent(text)
            || isCurrentPageInfoIntent(text)
    }

    private func shouldAcceptCodexOffer(_ text: String) -> Bool {
        guard pendingCodexActionPrompt != nil else {
            return false
        }

        let normalized = text.lowercased()
        let acceptPhrases = [
            "yes",
            "yeah",
            "yep",
            "use codex",
            "do it",
            "go ahead",
            "please do",
            "run it"
        ]

        return acceptPhrases.contains { normalized.contains($0) }
    }

    private func shouldDeclineCodexOffer(_ text: String) -> Bool {
        guard pendingGuidancePrompt != nil else {
            return false
        }

        let normalized = text.lowercased()
        let guidancePhrases = [
            "show me",
            "tell me",
            "steps",
            "walk me",
            "guide me",
            "instructions",
            "no",
            "not codex"
        ]

        return guidancePhrases.contains { normalized.contains($0) }
    }

    private func offerCodexAutomation(for userPrompt: String) {
        let actionPrompt = actionPromptForAutomationOffer(userPrompt)
        pendingCodexActionPrompt = actionPrompt
        pendingGuidancePrompt = userPrompt
        pendingCodexActionOffer = actionPrompt
        latestCodexBridgeResult = nil
        errorMessage = nil
        summonHint = "Codex can do this for you, or I can walk you through the steps."

        let offer = "I can use Codex to do that for you, or I can just tell you the steps. Which would you prefer?"
        memoryStore.append(InteractionMemoryEntry(
            userText: userPrompt,
            intent: .codexOffer,
            status: .offered,
            assistantText: offer
        ))
        cursorCompanionController.showAnswer(
            title: "I can do that",
            text: offer,
            activity: .speaking,
            collapseAfter: nil
        )
        spokenAnswerService.speak(offer)
        scheduleSpeakingStateReset()
    }

    private func clearPendingCodexOffer() {
        pendingCodexActionOffer = nil
        pendingCodexActionPrompt = nil
        pendingGuidancePrompt = nil
    }

    private func isHelpIntent(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let prefixes = [
            "how do i",
            "how can i",
            "how would i",
            "what is the best way",
            "what's the best way",
            "where do i"
        ]

        return prefixes.contains { normalized.hasPrefix($0) }
    }

    private func isBrowserSaveToDesktopIntent(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let saveWords = ["download", "save", "export", "capture"]
        let pageWords = ["page", "webpage", "website", "site", "browser", "url", "this"]

        return saveWords.contains { normalized.contains($0) }
            && pageWords.contains { normalized.contains($0) }
            && normalized.contains("desktop")
    }

    private func isScreenshotIntent(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let screenshotPhrases = [
            "take a screenshot",
            "take screenshot",
            "capture the screen",
            "capture my screen",
            "screenshot this",
            "save a screenshot",
            "screen shot"
        ]

        return screenshotPhrases.contains { normalized.contains($0) }
            && !normalized.contains("script")
            && !normalized.contains("python")
            && !normalized.contains("code")
    }

    private func isCopyURLIntent(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("copy")
            && (normalized.contains("url") || normalized.contains("link") || normalized.contains("current page"))
    }

    private func isPageMarkdownIntent(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return (normalized.contains("save") || normalized.contains("export") || normalized.contains("capture"))
            && (normalized.contains("markdown") || normalized.contains("notes") || normalized.contains(".md"))
            && (normalized.contains("page") || normalized.contains("webpage") || normalized.contains("website") || normalized.contains("this"))
    }

    private func isCreateDesktopFolderIntent(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return (normalized.contains("create") || normalized.contains("make") || normalized.contains("new"))
            && (normalized.contains("folder") || normalized.contains("directory"))
            && normalized.contains("desktop")
    }

    private func isCurrentPageInfoIntent(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let phrases = [
            "what page am i on",
            "what website am i on",
            "what url am i on",
            "what is this page",
            "where am i on the web"
        ]

        return phrases.contains { normalized.contains($0) }
    }

    private func isScriptCreationIntent(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let creationWords = ["create", "write", "make", "generate", "build"]
        let scriptWords = ["script", "python", ".py", "code", "program"]

        return creationWords.contains { normalized.contains($0) }
            && scriptWords.contains { normalized.contains($0) }
    }

    private func actionPromptForAutomationOffer(_ userPrompt: String) -> String {
        actionRouter.actionPromptForAutomationOffer(userPrompt)
    }

    private func completionText(for result: CodexBridgeResult) -> String {
        guard let finalMessage = result.finalMessage, !finalMessage.isEmpty else {
            return "Done. I finished the Codex task. Do you want to check the result?"
        }

        if finalMessage.lowercased().contains("screenshot") {
            return "Done. I saved the screenshot to your Desktop. Do you want me to open it in Finder?"
        }

        if finalMessage.lowercased().contains("clipboard") {
            return "Done. I copied it to your clipboard."
        }

        if finalMessage.lowercased().contains("you are on:") {
            return finalMessage.components(separatedBy: .newlines).prefix(2).joined(separator: ". ")
        }

        if finalMessage.lowercased().contains("desktop") {
            return "Done. I saved it to your Desktop. Do you want to go to your Desktop and check if the file is there?"
        }

        return "Done. Codex finished the task. Do you want to check the generated workspace?"
    }

    private func codexActionProfile(for text: String) -> String {
        actionRouter.profile(for: text)
    }

    private func progressText(forCodexProfile profile: String) -> String {
        switch profile {
        case "browser":
            return "Preparing a safe browser-control task. I will avoid final clicks like print or submit unless you confirm."
        case "mcp":
            return "Preparing an MCP-oriented Codex task and scaffold."
        case "files":
            return "Preparing a file or script artifact in a local Codex workspace."
        case "mac":
            return "Preparing a Mac action with a confirmation step for anything outside the workspace."
        default:
            return "Preparing a safe local Codex task."
        }
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
