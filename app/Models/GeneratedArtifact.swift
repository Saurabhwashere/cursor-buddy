import Foundation

struct GeneratedArtifact: Identifiable, Equatable {
    let id: UUID
    let name: String
    let type: ArtifactType
    let description: String
    let markdown: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        type: ArtifactType,
        description: String,
        markdown: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.description = description
        self.markdown = markdown
        self.createdAt = createdAt
    }
}

enum ArtifactType: String, Codable {
    case guide
    case checklist
}

struct ArtifactManifest: Codable {
    let name: String
    let type: ArtifactType
    let description: String
    let createdAt: String
    let source: String
    let markdownFile: String
}
