import AVFoundation
import CoreGraphics
import Foundation
import Speech

struct PermissionStatusService {
    func currentStatuses() -> [PermissionStatus] {
        [
            PermissionStatus(
                id: "api-key",
                title: "API key",
                state: hasAPIKey ? .ready : .missing
            ),
            PermissionStatus(
                id: "screen-recording",
                title: "Screen",
                state: CGPreflightScreenCaptureAccess() ? .ready : .missing
            ),
            PermissionStatus(
                id: "microphone",
                title: "Mic",
                state: microphoneState
            ),
            PermissionStatus(
                id: "speech",
                title: "Speech",
                state: speechState
            )
        ]
    }

    private var hasAPIKey: Bool {
        guard let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] else {
            return false
        }

        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var microphoneState: PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .ready
        case .notDetermined:
            return .unknown
        case .denied, .restricted:
            return .missing
        @unknown default:
            return .unknown
        }
    }

    private var speechState: PermissionState {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return .ready
        case .notDetermined:
            return .unknown
        case .denied, .restricted:
            return .missing
        @unknown default:
            return .unknown
        }
    }
}
