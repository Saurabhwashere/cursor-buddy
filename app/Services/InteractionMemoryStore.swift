import Foundation

final class InteractionMemoryStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private(set) var entries: [InteractionMemoryEntry] = []

    init(fileURL: URL? = nil) {
        let defaultURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("generated-tools/memory", isDirectory: true)
            .appendingPathComponent("interaction-memory.json")
        self.fileURL = fileURL ?? defaultURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    @discardableResult
    func append(_ entry: InteractionMemoryEntry) -> InteractionMemoryEntry {
        entries.append(entry)
        trim()
        save()
        return entry
    }

    func update(
        id: UUID,
        status: InteractionStatus,
        assistantText: String? = nil,
        artifactPath: String? = nil,
        workspacePath: String? = nil,
        errorMessage: String? = nil
    ) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            return
        }

        entries[index].updatedAt = Date()
        entries[index].status = status
        entries[index].assistantText = assistantText ?? entries[index].assistantText
        entries[index].artifactPath = artifactPath ?? entries[index].artifactPath
        entries[index].workspacePath = workspacePath ?? entries[index].workspacePath
        entries[index].errorMessage = errorMessage ?? entries[index].errorMessage
        save()
    }

    func latestAction() -> InteractionMemoryEntry? {
        entries.reversed().first { entry in
            switch entry.intent {
            case .saveWebpageToDesktop, .savePageMarkdownToDesktop, .takeScreenshotToDesktop, .copyURLToClipboard, .createDesktopFolder, .currentPageInfo, .codexAction:
                return true
            case .screenGuidance, .codexOffer:
                return false
            }
        }
    }

    func recentSummary(limit: Int = 6) -> String {
        entries.suffix(limit).map { entry in
            var parts = [
                "User: \(entry.userText)",
                "Intent: \(entry.intent.rawValue)",
                "Status: \(entry.status.rawValue)"
            ]

            if let artifactPath = entry.artifactPath {
                parts.append("Artifact: \(artifactPath)")
            }

            if let workspacePath = entry.workspacePath {
                parts.append("Workspace: \(workspacePath)")
            }

            if let errorMessage = entry.errorMessage {
                parts.append("Error: \(errorMessage)")
            }

            if let assistantText = entry.assistantText {
                parts.append("Assistant: \(assistantText)")
            }

            return parts.joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            entries = []
            return
        }

        entries = (try? decoder.decode([InteractionMemoryEntry].self, from: data)) ?? []
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Memory should improve the app, not break the main user flow.
        }
    }

    private func trim() {
        let maxEntries = 80
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }
}
