import SwiftUI

struct PointerOverlay: View {
    let points: [OverlayPoint]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(points) { point in
                    PointerMarker(point: point, containerSize: proxy.size)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
        }
    }
}

private struct PointerMarker: View {
    let point: OverlayPoint
    let containerSize: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            Circle()
                .stroke(Color.orange, lineWidth: 4)
                .frame(width: 44, height: 44)
                .shadow(color: .black.opacity(0.45), radius: 8)
                .position(x: point.x, y: point.y)

            Circle()
                .fill(Color.orange)
                .frame(width: 12, height: 12)
                .position(x: point.x, y: point.y)

            Text(point.label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
                .frame(maxWidth: 220, alignment: .leading)
                .position(labelPosition)
        }
    }

    private var labelPosition: CGPoint {
        let xOffset = point.x > Double(containerSize.width) - 260 ? -130.0 : 130.0
        let yOffset = point.y > Double(containerSize.height) - 90 ? -48.0 : 48.0
        return CGPoint(x: point.x + xOffset, y: point.y + yOffset)
    }
}
