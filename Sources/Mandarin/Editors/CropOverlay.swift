import SwiftUI

/// Draws a draggable crop box over an image shown in `display` (view points).
/// `crop` is in image pixels; `imageSize` is the pixel size the crop lives in.
struct CropOverlay: View {
    let imageSize: CGSize
    let crop: CGRect
    let display: CGRect
    let onDrag: (CGPoint, CGPoint) -> Void
    let onEnd: () -> Void
    let onNudge: (CGFloat, CGFloat) -> Void

    private var box: CGRect {
        let s = display.width / max(imageSize.width, 1)
        return CGRect(x: display.minX + crop.minX * s, y: display.minY + crop.minY * s, width: crop.width * s, height: crop.height * s)
    }

    var body: some View {
        ZStack {
            Path { path in
                path.addRect(display)
                path.addRect(box)
            }
            .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)

            Path { path in
                path.addRect(box)
                for i in 1...2 {
                    let f = CGFloat(i) / 3
                    path.move(to: CGPoint(x: box.minX + box.width * f, y: box.minY))
                    path.addLine(to: CGPoint(x: box.minX + box.width * f, y: box.maxY))
                    path.move(to: CGPoint(x: box.minX, y: box.minY + box.height * f))
                    path.addLine(to: CGPoint(x: box.maxX, y: box.minY + box.height * f))
                }
            }
            .stroke(Color.white.opacity(0.9), lineWidth: 1)
            .allowsHitTesting(false)

            ForEach(Array(corners.enumerated()), id: \.offset) { _, point in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.black.opacity(0.5), lineWidth: 1))
                    .frame(width: 10, height: 10)
                    .position(point)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { onDrag($0.startLocation, $0.location) }
                .onEnded { _ in onEnd() }
        )
        .focusable()
        .onMoveCommand { direction in
            switch direction {
            case .left: onNudge(-1, 0)
            case .right: onNudge(1, 0)
            case .up: onNudge(0, -1)
            case .down: onNudge(0, 1)
            @unknown default: break
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Crop box")
        .accessibilityValue("Left \(Int(crop.minX)), top \(Int(crop.minY)), \(Int(crop.width)) by \(Int(crop.height)) pixels")
        .accessibilityHint("Use the arrow keys to move it, or edit the crop fields in the side panel.")
    }

    private var corners: [CGPoint] {
        [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
         CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.maxX, y: box.maxY),
         CGPoint(x: box.midX, y: box.minY), CGPoint(x: box.midX, y: box.maxY),
         CGPoint(x: box.minX, y: box.midY), CGPoint(x: box.maxX, y: box.midY)]
    }
}
