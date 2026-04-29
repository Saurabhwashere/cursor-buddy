import AppKit
import CoreGraphics
import Foundation

enum ScreenshotError: LocalizedError {
    case permissionDenied
    case captureFailed
    case imageEncodingFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen recording permission is required. Enable it in System Settings > Privacy & Security > Screen & System Audio Recording, then reopen the app."
        case .captureFailed:
            return "Could not capture the current screen."
        case .imageEncodingFailed:
            return "Could not encode the screenshot."
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

        let maxDimension = Int(ProcessInfo.processInfo.environment["CODEX_CURSOR_MAX_SCREENSHOT_DIMENSION"] ?? "1280") ?? 1280
        let compressedImage = resize(image, maxDimension: maxDimension)
        let bitmap = NSBitmapImageRep(cgImage: compressedImage)
        guard let imageData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.72]) else {
            throw ScreenshotError.imageEncodingFailed
        }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-cursor-latest-screen-\(UUID().uuidString).jpg")

        do {
            try imageData.write(to: fileURL, options: [.atomic])
        } catch {
            throw ScreenshotError.writeFailed
        }

        return CapturedScreenshot(
            fileURL: fileURL,
            imageData: imageData,
            mimeType: "image/jpeg",
            width: compressedImage.width,
            height: compressedImage.height,
            originalWidth: image.width,
            originalHeight: image.height,
            scale: Double(NSScreen.main?.backingScaleFactor ?? 1.0)
        )
    }

    private func resize(_ image: CGImage, maxDimension: Int) -> CGImage {
        guard maxDimension > 0,
              max(image.width, image.height) > maxDimension else {
            return image
        }

        let scale = Double(maxDimension) / Double(max(image.width, image.height))
        let width = max(1, Int(Double(image.width) * scale))
        let height = max(1, Int(Double(image.height) * scale))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return image
        }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    private func hasScreenCapturePermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    private func requestScreenCapturePermission() {
        CGRequestScreenCaptureAccess()
    }
}
