import AppKit
import Foundation

struct CoordinateMapper {
    func map(
        points: [PointerPoint],
        from screenshot: CapturedScreenshot,
        to screen: NSScreen
    ) -> [OverlayPoint] {
        guard screenshot.width > 0, screenshot.height > 0 else {
            return []
        }

        let xScale = Double(screen.frame.width) / Double(screenshot.width)
        let yScale = Double(screen.frame.height) / Double(screenshot.height)

        return points.map { point in
            OverlayPoint(
                x: clamp(point.x * xScale, min: 0, max: Double(screen.frame.width)),
                y: clamp(point.y * yScale, min: 0, max: Double(screen.frame.height)),
                label: point.label
            )
        }
    }

    private func clamp(_ value: Double, min minimum: Double, max maximum: Double) -> Double {
        Swift.max(minimum, Swift.min(maximum, value))
    }
}
