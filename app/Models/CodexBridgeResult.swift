import Foundation

struct CodexBridgeResult: Codable, Equatable {
    let ok: Bool
    let taskId: String?
    let workspace: String?
    let finalMessage: String?
    let error: String?
}
