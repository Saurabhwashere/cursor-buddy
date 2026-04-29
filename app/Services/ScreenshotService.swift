import AppKit
import CoreGraphics
import Foundation

enum ScreenshotError: LocalizedError {
    case permissionDenied
    case captureFailed
    case pngEncodingFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen recording permission is required. Enable it in System Settings > Privacy & Security > Screen & System Audio Recording, then reopen the app."
        case .captureFailed:
            return "Could not capture the current screen."
        case .pngEncodingFailed:
            return "Could not encode the screenshot as PNG."
        case .writeFailed:
            return "Could not save the screenshot to a temporary file."
        }
    }
}

struct ScreenshotService {
    func captureFullScreen() throws -> CapturedScreenshot {
        guard hasScreenCapturePermission() else {
            requestScreenCapturePermission()
            throw ScreenshotError.permissionDenied
        }

        guard let image = CGWindowListCreateImage(
            .infinite,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else {
            throw ScreenshotError.captureFailed
        }

        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ScreenshotError.pngEncodingFailed
        }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-cursor-latest-screen-\(UUID().uuidString).png")

        do {
            try pngData.write(to: fileURL, options: [.atomic])
        } catch {
            throw ScreenshotError.writeFailed
        }

        return CapturedScreenshot(
            fileURL: fileURL,
            pngData: pngData,
            width: image.width,
            height: image.height,
            scale: Double(NSScreen.main?.backingScaleFactor ?? 1.0)
        )
    }

    private func hasScreenCapturePermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    private func requestScreenCapturePermission() {
        CGRequestScreenCaptureAccess()
    }
}
