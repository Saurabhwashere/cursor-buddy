import AppKit
import SwiftUI

@MainActor
final class CursorCompanionState: ObservableObject {
    @Published var status = "Ready"
    @Published var detailText = ""
    @Published var activity: CursorCompanionActivity = .idle
    @Published var presentation: CursorCompanionPresentation = .compact
    @Published var isVisible = true
}

enum CursorCompanionActivity {
    case idle
    case listening
    case thinking
    case speaking
}

enum CursorCompanionPresentation {
    case compact
    case label
    case answer
}

final class CursorCompanionOverlayWindow: NSPanel {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        ignoresMouseEvents = true
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .transient
        ]
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
    private var answerCollapseTask: Task<Void, Never>?
    private var refreshTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var lastScreenSignature = ""

    func start() {
        rebuildOverlayWindows()
        installObservers()
        startRefreshTimer()
        showIcon(status: "Ready")
    }

    func showIcon(status: String, isLoading: Bool = false) {
        state.status = status
        state.detailText = ""
        state.activity = isLoading ? .thinking : .idle
        state.presentation = .compact
        state.isVisible = true
        orderFront()
    }

    func showLabel(status: String, isLoading: Bool = false, collapseAfter seconds: UInt64 = 2) {
        state.status = status
        state.detailText = ""
        state.activity = isLoading ? .thinking : .idle
        state.presentation = .label
        state.isVisible = true
        orderFront()

        labelCollapseTask?.cancel()
        labelCollapseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            if self?.state.presentation == .label {
                self?.state.presentation = .compact
            }
        }
    }

    func showAnswer(
        title: String,
        text: String,
        activity: CursorCompanionActivity = .idle,
        collapseAfter seconds: UInt64? = 8
    ) {
        state.status = title
        state.detailText = text
        state.activity = activity
        state.presentation = .answer
        state.isVisible = true
        orderFront()

        answerCollapseTask?.cancel()
        guard let seconds else {
            answerCollapseTask = nil
            return
        }

        answerCollapseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            if self?.state.presentation == .answer,
               self?.state.activity == activity {
                self?.showIcon(status: "Ready")
            }
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
        lastScreenSignature = screenSignature
    }

    private func orderFront() {
        if windows.count != NSScreen.screens.count || lastScreenSignature != screenSignature {
            rebuildOverlayWindows()
        }

        windows.forEach { window in
            window.level = .screenSaver
            window.orderFrontRegardless()
        }
    }

    private func startRefreshTimer() {
        guard refreshTimer == nil else {
            return
        }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state.isVisible else {
                    return
                }

                self.orderFront()
            }
        }

        if let refreshTimer {
            RunLoop.main.add(refreshTimer, forMode: .common)
        }
    }

    private func installObservers() {
        guard observers.isEmpty else {
            return
        }

        let notificationCenter = NotificationCenter.default
        observers.append(notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.rebuildOverlayWindows()
                self?.orderFront()
            }
        })

        observers.append(notificationCenter.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.rebuildOverlayWindows()
                self?.orderFront()
            }
        })

        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.orderFront()
                try? await Task.sleep(nanoseconds: 150_000_000)
                self?.orderFront()
            }
        })
    }

    private var screenSignature: String {
        NSScreen.screens
            .map { screen in
                let frame = screen.frame
                return "\(Int(frame.origin.x)),\(Int(frame.origin.y)),\(Int(frame.width)),\(Int(frame.height))"
            }
            .joined(separator: "|")
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
                activity: state.activity,
                presentation: state.presentation,
                detailText: state.detailText
            )
            .opacity(state.isVisible && isCursorOnThisScreen ? 1 : 0)
            .position(clampedBubbleCenter(for: bubbleSize))
            .animation(.spring(response: 0.2, dampingFraction: 0.72, blendDuration: 0), value: cursorPosition)
            .animation(.easeInOut(duration: 0.12), value: isCursorOnThisScreen)
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: state.presentation)
        }
        .frame(width: screenFrame.width, height: screenFrame.height)
        .ignoresSafeArea()
        .onAppear(perform: startTrackingCursor)
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private var bubbleSize: CGSize {
        switch state.presentation {
        case .compact:
            return CGSize(width: 38, height: 38)
        case .label:
            return CGSize(width: 128, height: 46)
        case .answer:
            return CGSize(width: 340, height: 112)
        }
    }

    private func clampedBubbleCenter(for size: CGSize) -> CGPoint {
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        let expandedXOffset = max(0, (size.width - 38) / 2)
        let expandedYOffset = state.presentation == .answer ? 34.0 : 0.0
        let desiredCenter = CGPoint(
            x: cursorPosition.x + expandedXOffset,
            y: cursorPosition.y + expandedYOffset
        )

        return CGPoint(
            x: min(max(desiredCenter.x, halfWidth + 8), screenFrame.width - halfWidth - 8),
            y: min(max(desiredCenter.y, halfHeight + 8), screenFrame.height - halfHeight - 8)
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
