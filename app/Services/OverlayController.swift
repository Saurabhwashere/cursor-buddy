import AppKit
import SwiftUI

@MainActor
final class OverlayController {
    private let coordinateMapper: CoordinateMapper
    private var window: NSWindow?
    private var dismissTask: Task<Void, Never>?

    init(coordinateMapper: CoordinateMapper = CoordinateMapper()) {
        self.coordinateMapper = coordinateMapper
    }

    func show(points: [PointerPoint], for screenshot: CapturedScreenshot, timeoutSeconds: UInt64 = 10) {
        guard let screen = NSScreen.main else {
            hide()
            return
        }

        let overlayPoints = coordinateMapper.map(points: points, from: screenshot, to: screen)
        guard !overlayPoints.isEmpty else {
            hide()
            return
        }

        let overlayWindow = window ?? makeWindow(for: screen)
        overlayWindow.setFrame(screen.frame, display: true)
        overlayWindow.contentView = NSHostingView(
            rootView: PointerOverlay(points: overlayPoints)
        )
        overlayWindow.orderFrontRegardless()
        window = overlayWindow

        scheduleDismiss(after: timeoutSeconds)
    }

    func hide() {
        dismissTask?.cancel()
        dismissTask = nil
        window?.orderOut(nil)
    }

    private func makeWindow(for screen: NSScreen) -> NSWindow {
        let window = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .screenSaver
        window.ignoresMouseEvents = true
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .stationary
        ]
        return window
    }

    private func scheduleDismiss(after seconds: UInt64) {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            self?.hide()
        }
    }
}
