import SwiftUI

private struct WheelWedge: Shape {
    let startDegrees: Double
    let endDegrees: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let outerPoints = stride(from: startDegrees, through: endDegrees, by: 2.0).map {
            WheelGeometry.point(atDegrees: $0, radius: WheelGeometry.outerRadius)
        }
        let innerPoints = stride(from: endDegrees, through: startDegrees, by: -2.0).map {
            WheelGeometry.point(atDegrees: $0, radius: WheelGeometry.innerRadius)
        }
        guard let first = outerPoints.first else { return path }
        path.move(to: first)
        outerPoints.dropFirst().forEach { path.addLine(to: $0) }
        innerPoints.forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }
}

struct WheelView: View {
    @ObservedObject var model: WheelViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Below this angular width per segment, the text label is dropped and
    /// only the icon is shown, so a wheel with many targets still reads
    /// cleanly instead of overlapping labels.
    private static let labelAngleThreshold: Double = 40

    private var kindSymbol: String {
        switch model.kind {
        case .convert: return "arrow.triangle.2.circlepath"
        case .fileTools: return "wrench.and.screwdriver"
        case .fileActions: return "bolt.fill"
        }
    }

    var body: some View {
        let size = WheelGeometry.panelSize
        let count = model.segments.count
        let showLabels = count == 0 || (360.0 / Double(count)) >= Self.labelAngleThreshold

        ZStack {
            Circle()
                .fill(.thickMaterial)
                .frame(width: WheelGeometry.outerRadius * 2, height: WheelGeometry.outerRadius * 2)
                .position(WheelGeometry.center)

            ForEach(Array(model.segments.enumerated()), id: \.element.id) { index, segment in
                let range = WheelGeometry.angleRange(index: index, count: count)
                let isHovered = model.hoveredIndex == index

                WheelWedge(startDegrees: range.start, endDegrees: range.end)
                    .fill(isHovered ? Color.accentColor : Color(nsColor: .windowBackgroundColor))
                    .overlay(
                        WheelWedge(startDegrees: range.start, endDegrees: range.end)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )

                let labelPoint = WheelGeometry.midpoint(index: index, count: count)
                VStack(spacing: 4) {
                    Image(systemName: segment.systemImage)
                        .font(.system(size: 18, weight: .medium))
                    if showLabels {
                        Text(segment.title)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(isHovered ? Color.white : Color.primary)
                .position(labelPoint)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(segment.accessibilityLabel)
                .accessibilityAddTraits(isHovered ? .isSelected : [])
            }

            if model.segments.isEmpty {
                Circle()
                    .fill(Color(nsColor: .underPageBackgroundColor))
                    .frame(width: WheelGeometry.outerRadius * 2, height: WheelGeometry.outerRadius * 2)
                    .position(WheelGeometry.center)

                VStack(spacing: 6) {
                    Image(systemName: "nosign")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(model.emptyStateMessage)
                        .font(.caption)
                        .bold()
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                        .frame(width: WheelGeometry.outerRadius * 1.5)
                }
                .position(WheelGeometry.center)
            } else {
                Circle()
                    .fill(Color(nsColor: .underPageBackgroundColor))
                    .frame(width: WheelGeometry.innerRadius * 2, height: WheelGeometry.innerRadius * 2)
                    .position(WheelGeometry.center)

                VStack(spacing: 2) {
                    Image(systemName: kindSymbol)
                        .font(.system(size: 16, weight: .semibold))
                    Text(model.kind.title)
                        .font(.caption2)
                        .bold()
                }
                .position(WheelGeometry.center)
            }
        }
        .frame(width: size, height: size)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: model.hoveredIndex)
        .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
    }
}
