import Foundation

enum InteractionIntent: String, Codable, Equatable {
    case screenGuidance
    case saveWebpageToDesktop
    case savePageMarkdownToDesktop
    case takeScreenshotToDesktop
    case copyURLToClipboard
    case createDesktopFolder
    case currentPageInfo
    case codexAction
    case codexOffer
}

enum InteractionStatus: String, Codable, Equatable {
    case offered
    case running
    case succeeded
    case failed
    case answered
}

struct InteractionMemoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    var updatedAt: Date
    let userText: String
    let intent: InteractionIntent
    var status: InteractionStatus
    var assistantText: String?
    var artifactPath: String?
    var workspacePath: String?
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        userText: String,
        intent: InteractionIntent,
        status: InteractionStatus,
        assistantText: String? = nil,
        artifactPath: String? = nil,
        workspacePath: String? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.userText = userText
        self.intent = intent
        self.status = status
        self.assistantText = assistantText
        self.artifactPath = artifactPath
        self.workspacePath = workspacePath
        self.errorMessage = errorMessage
    }
}
