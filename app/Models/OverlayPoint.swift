import Foundation

struct OverlayPoint: Identifiable, Equatable {
    let id: UUID
    let x: Double
    let y: Double
    let label: String

    init(id: UUID = UUID(), x: Double, y: Double, label: String) {
        self.id = id
        self.x = x
        self.y = y
        self.label = label
    }
}
