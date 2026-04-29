import Foundation

enum PermissionState: Equatable {
    case ready
    case missing
    case unknown

    var title: String {
        switch self {
        case .ready:
            return "Ready"
        case .missing:
            return "Needs setup"
        case .unknown:
            return "Not checked"
        }
    }
}

struct PermissionStatus: Identifiable, Equatable {
    let id: String
    let title: String
    let state: PermissionState
}
