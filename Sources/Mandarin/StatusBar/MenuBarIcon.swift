import AppKit

/// The menu-bar glyph: a ring with a dot in the middle (a file about to be
/// dropped on a wheel). Drawn as a vector so it stays crisp at 1x/2x; being
/// a template image, macOS tints it for light, dark and highlighted bars.
public enum MenuBarIcon {
    public static func image(pointSize: CGFloat = 18) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: size, flipped: false) { rect in
            let ring = rect.width * 0.1
            let ringRect = rect.insetBy(dx: rect.width * 0.14 + ring / 2, dy: rect.height * 0.14 + ring / 2)
            let path = NSBezierPath(ovalIn: ringRect)
            path.lineWidth = ring
            NSColor.black.setStroke()
            path.stroke()
            let dot = rect.width * 0.3
            let dotRect = NSRect(x: rect.midX - dot / 2, y: rect.midY - dot / 2, width: dot, height: dot)
            NSColor.black.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = AppIdentity.name
        return image
    }
}
