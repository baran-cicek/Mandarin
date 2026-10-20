import CoreGraphics
import Foundation

/// Single source of truth for the wheel's layout, shared by the SwiftUI
/// drawing code and the AppKit drag hit-testing code so they never drift.
enum WheelGeometry {
    static let panelSize: CGFloat = 260
    static let outerRadius: CGFloat = 120
    static let innerRadius: CGFloat = 42
    static let gapDegrees: Double = 3

    static var center: CGPoint {
        CGPoint(x: panelSize / 2, y: panelSize / 2)
    }

    /// Angle range for segment `index` out of `count`, measured clockwise
    /// from the top (12 o'clock), in degrees, with a small gap on each side.
    static func angleRange(index: Int, count: Int) -> (start: Double, end: Double) {
        let step = 360.0 / Double(count)
        let start = Double(index) * step + gapDegrees / 2
        let end = Double(index + 1) * step - gapDegrees / 2
        return (start, end)
    }

    static func midpoint(index: Int, count: Int) -> CGPoint {
        let range = angleRange(index: index, count: count)
        let midDegrees = (range.start + range.end) / 2
        let midRadius = (innerRadius + outerRadius) / 2
        return point(atDegrees: midDegrees, radius: midRadius)
    }

    static func point(atDegrees degrees: Double, radius: CGFloat) -> CGPoint {
        let radians = (degrees - 90) * .pi / 180
        return CGPoint(
            x: center.x + radius * CGFloat(cos(radians)),
            y: center.y + radius * CGFloat(sin(radians))
        )
    }

    /// Returns the segment index under `point` (view-coordinates, origin
    /// top-left, y-down), or nil if outside the ring or over the center hole.
    static func segmentIndex(at point: CGPoint, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = sqrt(dx * dx + dy * dy)
        guard distance >= innerRadius, distance <= outerRadius else { return nil }

        // Angle clockwise from top, 0..<360.
        var degrees = atan2(dx, -dy) * 180 / .pi
        if degrees < 0 { degrees += 360 }

        let step = 360.0 / Double(count)
        let index = Int(degrees / step)
        return min(max(index, 0), count - 1)
    }
}
