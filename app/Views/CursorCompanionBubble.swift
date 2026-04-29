import SwiftUI

struct CursorCompanionBubble: View {
    let status: String
    let activity: CursorCompanionActivity
    let presentation: CursorCompanionPresentation
    let detailText: String

    var body: some View {
        HStack(spacing: 9) {
            icon

            switch presentation {
            case .compact:
                EmptyView()
            case .label:
                labelContent
            case .answer:
                answerContent
            }
        }
        .padding(.leading, presentation == .compact ? 5 : 8)
        .padding(.trailing, presentation == .compact ? 5 : 12)
        .padding(.vertical, presentation == .compact ? 5 : 7)
        .background(.black.opacity(0.86), in: Capsule())
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 14, x: 0, y: 8)
    }

    private var labelContent: some View {
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

    private var answerContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(status)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)

                if activity == .thinking {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white)
                }
            }

            Text(detailText.isEmpty ? "..." : detailText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.84))
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 270, alignment: .leading)
        .padding(.vertical, 3)
    }

    private var icon: some View {
        ZStack {
            if activity == .listening {
                ListeningPulse()
            }

            Circle()
                .fill(.black)
                .frame(width: 30, height: 30)

            Circle()
                .stroke(.white.opacity(0.18), lineWidth: 1)
                .frame(width: 29, height: 29)

            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: 24, height: 24)

            OpenAIMark()
                .stroke(.white, style: StrokeStyle(lineWidth: 1.85, lineCap: .round, lineJoin: .round))
                .frame(width: 17, height: 17)
                .opacity(activity == .speaking ? 0.28 : 1)

            switch activity {
            case .idle:
                EmptyView()
            case .listening:
                Circle()
                    .stroke(.white.opacity(0.42), lineWidth: 1.3)
                    .frame(width: 34, height: 34)
            case .thinking:
                ThinkingRing()
                    .frame(width: 36, height: 36)
            case .speaking:
                SpeakingWaveform()
                    .frame(width: 22, height: 18)
            }
        }
        .frame(width: 38, height: 38)
    }
}

private struct ListeningPulse: View {
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.18), lineWidth: 2)
                .frame(width: 34, height: 34)
                .scaleEffect(isPulsing ? 1.35 : 0.9)
                .opacity(isPulsing ? 0.05 : 0.55)

            Circle()
                .stroke(.white.opacity(0.16), lineWidth: 2)
                .frame(width: 34, height: 34)
                .scaleEffect(isPulsing ? 1.75 : 1.0)
                .opacity(isPulsing ? 0.02 : 0.38)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.0).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
    }
}

private struct ThinkingRing: View {
    @State private var rotation = 0.0

    var body: some View {
        Circle()
            .trim(from: 0.08, to: 0.72)
            .stroke(
                AngularGradient(
                    colors: [.white.opacity(0.1), .white.opacity(0.95)],
                    center: .center
                ),
                style: StrokeStyle(lineWidth: 2.1, lineCap: .round)
            )
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

private struct SpeakingWaveform: View {
    @State private var phase = false

    private let heights: [CGFloat] = [7, 13, 18, 11, 15]

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                Capsule()
                    .fill(.white)
                    .frame(width: 2.4, height: phase ? height : max(5, heights.reversed()[index]))
                    .animation(
                        .easeInOut(duration: 0.42)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.055),
                        value: phase
                    )
            }
        }
        .onAppear {
            phase = true
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
