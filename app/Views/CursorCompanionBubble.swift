import SwiftUI

struct CursorCompanionBubble: View {
    let status: String
    let isLoading: Bool
    let showsLabel: Bool

    var body: some View {
        HStack(spacing: 9) {
            icon

            if showsLabel {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Codex")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)

                    Text(status)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }
            }
        }
        .padding(.leading, showsLabel ? 8 : 5)
        .padding(.trailing, showsLabel ? 12 : 5)
        .padding(.vertical, showsLabel ? 7 : 5)
        .background(.black.opacity(0.86), in: Capsule())
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 14, x: 0, y: 8)
    }

    private var icon: some View {
        ZStack {
            Circle()
                .fill(.black)
                .frame(width: 30, height: 30)

            Circle()
                .stroke(.white.opacity(0.18), lineWidth: 1)
                .frame(width: 29, height: 29)

            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: 24, height: 24)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            } else {
                OpenAIMark()
                    .stroke(.white, style: StrokeStyle(lineWidth: 1.85, lineCap: .round, lineJoin: .round))
                    .frame(width: 17, height: 17)
            }
        }
    }
}

private struct OpenAIMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.25
        let loopLength = min(rect.width, rect.height) * 0.34
        let loopInset = min(rect.width, rect.height) * 0.12

        for index in 0..<6 {
            let angle = (Double(index) * 60.0 - 90.0) * .pi / 180.0
            let tangent = angle + .pi / 2.0
            let base = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            let start = CGPoint(
                x: base.x + cos(tangent) * loopInset,
                y: base.y + sin(tangent) * loopInset
            )
            let end = CGPoint(
                x: base.x + cos(tangent) * loopLength,
                y: base.y + sin(tangent) * loopLength
            )
            let control = CGPoint(
                x: center.x + cos(angle) * (radius + loopInset),
                y: center.y + sin(angle) * (radius + loopInset)
            )

            path.move(to: start)
            path.addQuadCurve(to: end, control: control)
        }

        path.addEllipse(in: CGRect(
            x: center.x - rect.width * 0.075,
            y: center.y - rect.height * 0.075,
            width: rect.width * 0.15,
            height: rect.height * 0.15
        ))

        return path
    }
}
