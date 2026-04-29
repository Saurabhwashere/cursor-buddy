import AppKit
import SwiftUI

@MainActor
final class CursorCompanionState: ObservableObject {
    @Published var status = "Ready"
    @Published var isLoading = false
    @Published var showsLabel = false
    @Published var isVisible = true
}

final class CursorCompanionOverlayWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        hasShadow = false
        hidesOnDeactivate = false
        setFrame(screen.frame, display: true)
        isExcludedFromWindowsMenu = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class CursorCompanionController {
    private let state = CursorCompanionState()
    private var windows: [CursorCompanionOverlayWindow] = []
    private var labelCollapseTask: Task<Void, Never>?

    func start() {
        rebuildOverlayWindows()
        showIcon(status: "Ready")
    }

    func showIcon(status: String, isLoading: Bool = false) {
        state.status = status
        state.isLoading = isLoading
        state.showsLabel = false
        state.isVisible = true
        orderFront()
    }

    func showLabel(status: String, isLoading: Bool = false, collapseAfter seconds: UInt64 = 2) {
        state.status = status
        state.isLoading = isLoading
        state.showsLabel = true
        state.isVisible = true
        orderFront()

        labelCollapseTask?.cancel()
        labelCollapseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            self?.state.showsLabel = false
        }
    }

    func hideForScreenshot() {
        state.isVisible = false
        windows.forEach { $0.orderOut(nil) }
    }

    func showAfterScreenshot() {
        state.isVisible = true
        orderFront()
    }

    private func rebuildOverlayWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.map { screen in
            let window = CursorCompanionOverlayWindow(screen: screen)
            window.contentView = NSHostingView(
                rootView: CursorCompanionOverlayView(
                    screenFrame: screen.frame,
                    state: state
                )
            )
            return window
        }
    }

    private func orderFront() {
        if windows.count != NSScreen.screens.count {
            rebuildOverlayWindows()
        }

        windows.forEach { $0.orderFrontRegardless() }
    }
}

private struct CursorCompanionOverlayView: View {
    let screenFrame: CGRect
    @ObservedObject var state: CursorCompanionState

    @State private var cursorPosition: CGPoint
    @State private var isCursorOnThisScreen: Bool
    @State private var timer: Timer?

    init(screenFrame: CGRect, state: CursorCompanionState) {
        self.screenFrame = screenFrame
        self.state = state

        let mouseLocation = NSEvent.mouseLocation
        let localPoint = Self.convertScreenPoint(mouseLocation, in: screenFrame)
        _cursorPosition = State(initialValue: Self.offsetBuddyPoint(localPoint))
        _isCursorOnThisScreen = State(initialValue: screenFrame.contains(mouseLocation))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001)

            CursorCompanionBubble(
                status: state.status,
                isLoading: state.isLoading,
                showsLabel: state.showsLabel
            )
            .opacity(state.isVisible && isCursorOnThisScreen ? 1 : 0)
            .position(clampedBubbleCenter)
            .animation(.spring(response: 0.2, dampingFraction: 0.72, blendDuration: 0), value: cursorPosition)
            .animation(.easeInOut(duration: 0.12), value: isCursorOnThisScreen)
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: state.showsLabel)
        }
        .frame(width: screenFrame.width, height: screenFrame.height)
        .ignoresSafeArea()
        .onAppear(perform: startTrackingCursor)
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private var clampedBubbleCenter: CGPoint {
        let size = state.showsLabel ? CGSize(width: 128, height: 46) : CGSize(width: 38, height: 38)
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        return CGPoint(
            x: min(max(cursorPosition.x, halfWidth + 8), screenFrame.width - halfWidth - 8),
            y: min(max(cursorPosition.y, halfHeight + 8), screenFrame.height - halfHeight - 8)
        )
    }

    private func startTrackingCursor() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            let mouseLocation = NSEvent.mouseLocation
            isCursorOnThisScreen = screenFrame.contains(mouseLocation)

            guard isCursorOnThisScreen else {
                return
            }

            let localPoint = Self.convertScreenPoint(mouseLocation, in: screenFrame)
            cursorPosition = Self.offsetBuddyPoint(localPoint)
        }

        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private static func convertScreenPoint(_ screenPoint: CGPoint, in screenFrame: CGRect) -> CGPoint {
        let x = screenPoint.x - screenFrame.origin.x
        let y = (screenFrame.origin.y + screenFrame.height) - screenPoint.y
        return CGPoint(x: x, y: y)
    }

    private static func offsetBuddyPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x + 35, y: point.y + 25)
    }
}
