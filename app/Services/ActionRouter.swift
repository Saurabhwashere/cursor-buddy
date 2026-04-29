import Foundation

enum MacAction: String, Equatable {
    case saveWebpageToDesktop
    case savePageMarkdownToDesktop
    case takeScreenshotToDesktop
    case copyURLToClipboard
    case createDesktopFolder
    case currentPageInfo
}

enum CodexAction: String, Equatable {
    case explicit
    case scriptCreation
}

enum ActionRoute: Equatable {
    case memoryFollowUp
    case acceptCodexOffer
    case declineCodexOffer
    case offerAutomation
    case macAction(MacAction)
    case codexAction(CodexAction)
    case riskCheck
    case screenGuidance
    case clarify(String)
}

struct RouterContext {
    let hasPendingCodexOffer: Bool
}

struct ActionRouter {
    func route(_ text: String, context: RouterContext) -> ActionRoute {
        if isMemoryFollowUp(text) {
            return .memoryFollowUp
        }

        if context.hasPendingCodexOffer && shouldAcceptCodexOffer(text) {
            return .acceptCodexOffer
        }

        if context.hasPendingCodexOffer && shouldDeclineCodexOffer(text) {
            return .declineCodexOffer
        }

        if isRiskCheckIntent(text) {
            return .riskCheck
        }

        if shouldRunWithCodex(text) {
            if isScriptCreationIntent(text) {
                return .codexAction(.scriptCreation)
            }

            return .codexAction(.explicit)
        }

        if isScriptCreationIntent(text) {
            return .codexAction(.scriptCreation)
        }

        if let macAction = macAction(for: text) {
            return .macAction(macAction)
        }

        if shouldOfferCodexAutomation(text) {
            return .offerAutomation
        }

        return .screenGuidance
    }

    func profile(for text: String) -> String {
        let normalized = text.lowercased()

        if normalized.contains("mcp") || normalized.contains("server") {
            return "mcp"
        }

        if isScriptCreationIntent(text) {
            return "files"
        }

        if isScreenshotIntent(text)
            || isCreateDesktopFolderIntent(text)
            || isCopyURLIntent(text)
            || isCurrentPageInfoIntent(text) {
            return "mac"
        }

        if isPageMarkdownIntent(text)
            || isBrowserSaveToDesktopIntent(text)
            || normalized.contains("browser")
            || normalized.contains("safari")
            || normalized.contains("chrome")
            || normalized.contains("page")
            || normalized.contains("print")
            || (normalized.contains("desktop")
                && (normalized.contains("save") || normalized.contains("download") || normalized.contains("export"))) {
            return "browser"
        }

        if normalized.contains("file")
            || normalized.contains("folder")
            || normalized.contains("document")
            || normalized.contains("script") {
            return "files"
        }

        if normalized.contains("app")
            || normalized.contains("window")
            || normalized.contains("mac") {
            return "mac"
        }

        return "general"
    }

    func memoryIntent(for text: String) -> InteractionIntent {
        if isBrowserSaveToDesktopIntent(text) {
            return .saveWebpageToDesktop
        }

        if isPageMarkdownIntent(text) {
            return .savePageMarkdownToDesktop
        }

        if isScreenshotIntent(text) {
            return .takeScreenshotToDesktop
        }

        if isCopyURLIntent(text) {
            return .copyURLToClipboard
        }

        if isCreateDesktopFolderIntent(text) {
            return .createDesktopFolder
        }

        if isCurrentPageInfoIntent(text) {
            return .currentPageInfo
        }

        return .codexAction
    }

    func actionPromptForAutomationOffer(_ userPrompt: String) -> String {
        if isBrowserSaveToDesktopIntent(userPrompt) {
            return "Use Codex to save this webpage to my Desktop."
        }

        return "Use Codex to help with this task: \(userPrompt)"
    }

    func isMemoryFollowUp(_ text: String) -> Bool {
        shouldRetryLastAction(text) || shouldRevealLastArtifact(text) || shouldAskAboutLatestAction(text)
    }

    func shouldRetryLastAction(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let phrases = [
            "try again",
            "retry",
            "do it again",
            "save it again",
            "download it again"
        ]

        return phrases.contains { normalized.contains($0) }
    }

    func shouldRevealLastArtifact(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let phrases = [
            "open it",
            "show it",
            "reveal it",
            "open desktop",
            "go to desktop",
            "show me the file",
            "open finder"
        ]

        return phrases.contains { normalized.contains($0) }
    }

    func shouldAskAboutLatestAction(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let phrases = [
            "where do i find it",
            "where is it",
            "where did you save",
            "where was it saved",
            "where's the file",
            "where is the file",
            "i can't see it",
            "i cannot see it",
            "can't find it",
            "cannot find it",
            "did it work",
            "is it there"
        ]

        return phrases.contains { normalized.contains($0) }
    }

    private func macAction(for text: String) -> MacAction? {
        if isBrowserSaveToDesktopIntent(text) && shouldDelegateBrowserSave(text) {
            return .saveWebpageToDesktop
        }

        if isPageMarkdownIntent(text) {
            return .savePageMarkdownToDesktop
        }

        if isScreenshotIntent(text) && !isHelpIntent(text) {
            return .takeScreenshotToDesktop
        }

        if isCopyURLIntent(text) {
            return .copyURLToClipboard
        }

        if isCreateDesktopFolderIntent(text) {
            return .createDesktopFolder
        }

        if isCurrentPageInfoIntent(text) {
            return .currentPageInfo
        }

        return nil
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

    private func shouldAcceptCodexOffer(_ text: String) -> Bool {
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

    private func isRiskCheckIntent(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let phrases = [
            "is this safe",
            "is it safe",
            "is this legit",
            "is this legitimate",
            "risk check",
            "check if this is safe",
            "should i trust"
        ]

        return phrases.contains { normalized.contains($0) }
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
}
