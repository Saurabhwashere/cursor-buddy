import AppKit
import Foundation

struct CoordinateMapper {
    private let targetSnapper = VisualTargetSnapper()

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
            let snappedPoint = targetSnapper.snap(point, in: screenshot)
            return OverlayPoint(
                x: clamp(snappedPoint.x * xScale, min: 0, max: Double(screen.frame.width)),
                y: clamp(snappedPoint.y * yScale, min: 0, max: Double(screen.frame.height)),
                label: snappedPoint.label
            )
        }
    }

    private func clamp(_ value: Double, min minimum: Double, max maximum: Double) -> Double {
        Swift.max(minimum, Swift.min(maximum, value))
    }
}

private struct VisualTargetSnapper {
    func snap(_ point: PointerPoint, in screenshot: CapturedScreenshot) -> PointerPoint {
        let label = point.label.lowercased()
        guard shouldSnapToFormField(label: label),
              let image = NSImage(data: screenshot.pngData),
              let bitmap = NSBitmapImageRep(data: screenshot.pngData) ?? image.representations.compactMap({ $0 as? NSBitmapImageRep }).first else {
            return point
        }

        let candidates = findFormFieldCandidates(in: bitmap)
        guard !candidates.isEmpty else {
            return point
        }

        let selected = chooseCandidate(
            from: candidates,
            for: label,
            fallbackPoint: CGPoint(x: point.x, y: point.y),
            imageHeight: bitmap.pixelsHigh
        )

        guard let selected else {
            return point
        }

        return PointerPoint(
            x: selected.rect.midX,
            y: selected.rect.midY,
            label: point.label
        )
    }

    private func shouldSnapToFormField(label: String) -> Bool {
        [
            "input",
            "field",
            "box",
            "username",
            "email",
            "password"
        ].contains { label.contains($0) }
    }

    private func findFormFieldCandidates(in bitmap: NSBitmapImageRep) -> [FieldCandidate] {
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        let minimumRunLength = max(180, Int(Double(width) * 0.22))
        var rowRuns: [RowRun] = []

        for y in stride(from: 0, to: height, by: 2) {
            if let run = longestBorderRun(in: bitmap, y: y, minimumRunLength: minimumRunLength) {
                rowRuns.append(run)
            }
        }

        let groupedRows = groupRuns(rowRuns)
        var candidates: [FieldCandidate] = []

        for topIndex in groupedRows.indices {
            let top = groupedRows[topIndex]

            for bottom in groupedRows.dropFirst(topIndex + 1) {
                let fieldHeight = bottom.y - top.y
                guard (34...180).contains(fieldHeight) else {
                    continue
                }

                guard abs(top.startX - bottom.startX) < 36,
                      abs(top.endX - bottom.endX) < 36 else {
                    continue
                }

                let startX = min(top.startX, bottom.startX)
                let endX = max(top.endX, bottom.endX)
                guard endX - startX >= minimumRunLength else {
                    continue
                }

                candidates.append(FieldCandidate(
                    rect: CGRect(
                        x: CGFloat(startX),
                        y: CGFloat(top.y),
                        width: CGFloat(endX - startX),
                        height: CGFloat(fieldHeight)
                    ),
                    style: top.style == .red || bottom.style == .red ? .red : .dark
                ))
                break
            }
        }

        return candidates
    }

    private func longestBorderRun(
        in bitmap: NSBitmapImageRep,
        y: Int,
        minimumRunLength: Int
    ) -> RowRun? {
        var best: RowRun?
        var currentStart: Int?
        var currentStyle: BorderStyle?
        var redCount = 0
        var darkCount = 0

        func finishRun(at endX: Int) {
            guard let start = currentStart else {
                return
            }

            let runLength = endX - start
            guard runLength >= minimumRunLength else {
                return
            }

            let style: BorderStyle = redCount >= darkCount ? .red : .dark
            let run = RowRun(y: y, startX: start, endX: endX, style: style)
            if best == nil || runLength > (best!.endX - best!.startX) {
                best = run
            }
        }

        for x in 0..<bitmap.pixelsWide {
            let style = borderStyle(atX: x, y: y, in: bitmap)
            if let style {
                if currentStart == nil {
                    currentStart = x
                    currentStyle = style
                    redCount = 0
                    darkCount = 0
                }

                if style == .red {
                    redCount += 1
                } else {
                    darkCount += 1
                }
                currentStyle = style
            } else {
                finishRun(at: x)
                currentStart = nil
                currentStyle = nil
                redCount = 0
                darkCount = 0
            }
        }

        finishRun(at: bitmap.pixelsWide - 1)
        _ = currentStyle
        return best
    }

    private func borderStyle(atX x: Int, y: Int, in bitmap: NSBitmapImageRep) -> BorderStyle? {
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
            return nil
        }

        let red = color.redComponent
        let green = color.greenComponent
        let blue = color.blueComponent

        if red > 0.55, green < 0.34, blue < 0.40 {
            return .red
        }

        if red < 0.18, green < 0.18, blue < 0.20 {
            return .dark
        }

        return nil
    }

    private func groupRuns(_ runs: [RowRun]) -> [RowRun] {
        var groups: [[RowRun]] = []

        for run in runs {
            if let last = groups.indices.last,
               let previous = groups[last].last,
               abs(previous.y - run.y) <= 6,
               abs(previous.startX - run.startX) <= 12,
               abs(previous.endX - run.endX) <= 12 {
                groups[last].append(run)
            } else {
                groups.append([run])
            }
        }

        return groups.compactMap { group in
            guard let first = group.first else {
                return nil
            }

            let y = group.map(\.y).reduce(0, +) / group.count
            let startX = group.map(\.startX).reduce(0, +) / group.count
            let endX = group.map(\.endX).reduce(0, +) / group.count
            let redRows = group.filter { $0.style == .red }.count
            let style: BorderStyle = redRows >= group.count - redRows ? .red : .dark
            return RowRun(y: y, startX: startX, endX: endX, style: style == .red ? .red : first.style)
        }
    }

    private func chooseCandidate(
        from candidates: [FieldCandidate],
        for label: String,
        fallbackPoint: CGPoint,
        imageHeight: Int
    ) -> FieldCandidate? {
        let fieldCandidates = candidates
            .filter { $0.rect.width > 220 && $0.rect.height > 30 }
            .sorted { $0.rect.minY < $1.rect.minY }

        guard !fieldCandidates.isEmpty else {
            return nil
        }

        if label.contains("username") || label.contains("email") {
            return fieldCandidates.first(where: { $0.style == .red }) ?? fieldCandidates.first
        }

        if label.contains("password") {
            return fieldCandidates.last(where: { $0.style == .dark }) ?? fieldCandidates.last
        }

        return fieldCandidates.min { lhs, rhs in
            distance(from: lhs.rect.center, to: fallbackPoint) < distance(from: rhs.rect.center, to: fallbackPoint)
        }
    }

    private func distance(from first: CGPoint, to second: CGPoint) -> Double {
        let dx = first.x - second.x
        let dy = first.y - second.y
        return Double((dx * dx + dy * dy).squareRoot())
    }
}

private struct RowRun {
    let y: Int
    let startX: Int
    let endX: Int
    let style: BorderStyle
}

private struct FieldCandidate {
    let rect: CGRect
    let style: BorderStyle
}

private enum BorderStyle {
    case red
    case dark
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
