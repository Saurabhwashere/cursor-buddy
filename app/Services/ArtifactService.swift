import Foundation

struct ArtifactService {
    func createGuide(
        prompt: String,
        mode: GuidanceMode,
        response: ScreenAnalysisResponse
    ) -> GeneratedArtifact {
        let title = response.checklist?.title ?? titleFrom(prompt: prompt)
        let name = slug(title)
        let markdown = guideMarkdown(title: title, prompt: prompt, mode: mode, response: response)

        return GeneratedArtifact(
            name: name,
            type: .guide,
            description: "Reusable guide generated from screen analysis.",
            markdown: markdown
        )
    }

    func save(_ artifact: GeneratedArtifact) throws -> URL {
        let baseDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("generated-tools/guides", isDirectory: true)
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

        let timestamp = timestamp(for: artifact.createdAt)
        let markdownFilename = "\(artifact.name)-\(timestamp).md"
        let manifestFilename = "\(artifact.name)-\(timestamp).manifest.json"
        let markdownURL = baseDirectory.appendingPathComponent(markdownFilename)
        let manifestURL = baseDirectory.appendingPathComponent(manifestFilename)

        try artifact.markdown.write(to: markdownURL, atomically: true, encoding: .utf8)

        let manifest = ArtifactManifest(
            name: artifact.name,
            type: artifact.type,
            description: artifact.description,
            createdAt: ISO8601DateFormatter().string(from: artifact.createdAt),
            source: "screen-analysis",
            markdownFile: markdownFilename
        )
        let manifestData = try JSONEncoder.prettyPrinted.encode(manifest)
        try manifestData.write(to: manifestURL, options: [.atomic])

        return markdownURL
    }

    private func guideMarkdown(
        title: String,
        prompt: String,
        mode: GuidanceMode,
        response: ScreenAnalysisResponse
    ) -> String {
        var sections: [String] = [
            "# \(title)",
            "Generated from Codex Cursor screen analysis.",
            "## Original Question\n\n\(prompt)",
            "## Mode\n\n\(mode.title)",
            "## Summary\n\n\(response.answer)"
        ]

        if !response.steps.isEmpty {
            let steps = response.steps
                .enumerated()
                .map { index, step in "\(index + 1). \(step)" }
                .joined(separator: "\n")
            sections.append("## Steps\n\n\(steps)")
        }

        if let checklist = response.checklist {
            let items = checklist.items
                .map { "- [ ] \($0)" }
                .joined(separator: "\n")
            sections.append("## \(checklist.title)\n\n\(items)")
        }

        if !response.riskWarnings.isEmpty {
            let warnings = response.riskWarnings
                .map { "- \($0)" }
                .joined(separator: "\n")
            sections.append("## Safety Notes\n\n\(warnings)")
        }

        if !response.points.isEmpty {
            let pointers = response.points
                .map { "- \($0.label): x \(Int($0.x)), y \(Int($0.y))" }
                .joined(separator: "\n")
            sections.append("## Screen Pointers\n\n\(pointers)")
        }

        return sections.joined(separator: "\n\n") + "\n"
    }

    private func titleFrom(prompt: String) -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Reusable Screen Guide"
        }

        return trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "?.!"))
            .capitalized
    }

    private func slug(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let scalars = text.lowercased().unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let slug = String(scalars)
            .split(separator: "-")
            .joined(separator: "-")
            .prefix(48)
        return slug.isEmpty ? "screen-guide" : String(slug)
    }

    private func timestamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}

private extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
