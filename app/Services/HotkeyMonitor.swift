import AppKit
import Foundation

@MainActor
final class HotkeyMonitor {
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var wasOptionDown = false
    private let onOptionDown: () -> Void
    private let onOptionUp: () -> Void

    init(onOptionDown: @escaping () -> Void, onOptionUp: @escaping () -> Void) {
        self.onOptionDown = onOptionDown
        self.onOptionUp = onOptionUp
    }

    func start() {
        stop()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }

        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }

        localMonitor = nil
        globalMonitor = nil
        wasOptionDown = false
    }

    private func handle(_ event: NSEvent) {
        let isOptionDown = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.option)

        if isOptionDown && !wasOptionDown {
            onOptionDown()
        } else if !isOptionDown && wasOptionDown {
            onOptionUp()
        }

        wasOptionDown = isOptionDown
    }

    deinit {
        localMonitor.map(NSEvent.removeMonitor)
        globalMonitor.map(NSEvent.removeMonitor)
    }
}
