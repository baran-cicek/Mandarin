import CoreGraphics

public enum AspectPreset: String, CaseIterable, Identifiable {
    case free, original, square, r4x3, r3x2, r16x9, r3x4, r2x3, r9x16

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .free: return "Free"
        case .original: return "Original"
        case .square: return "1:1"
        case .r4x3: return "4:3"
        case .r3x2: return "3:2"
        case .r16x9: return "16:9"
        case .r3x4: return "3:4"
        case .r2x3: return "2:3"
        case .r9x16: return "9:16"
        }
    }

    /// Width divided by height, or nil for a free-form box.
    public func ratio(originalSize: CGSize) -> CGFloat? {
        switch self {
        case .free: return nil
        case .original: return originalSize.height > 0 ? originalSize.width / originalSize.height : nil
        case .square: return 1
        case .r4x3: return 4.0 / 3
        case .r3x2: return 3.0 / 2
        case .r16x9: return 16.0 / 9
        case .r3x4: return 3.0 / 4
        case .r2x3: return 2.0 / 3
        case .r9x16: return 9.0 / 16
        }
    }
}

public enum CropHandle: Equatable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left, body
}

/// Pure geometry for a draggable crop box. Everything is in one coordinate
/// space with a top-left origin (image pixels, or view points); `bounds` is
/// the size of that space.
public enum CropGeometry {
    /// Largest rect of `content`'s aspect ratio that fits in `container`, centred.
    public static func fit(content: CGSize, in container: CGSize) -> CGRect {
        guard content.width > 0, content.height > 0, container.width > 0, container.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let scale = min(container.width / content.width, container.height / content.height)
        let size = CGSize(width: content.width * scale, height: content.height * scale)
        return CGRect(x: (container.width - size.width) / 2, y: (container.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    /// Whole area for a free box, otherwise the largest centred box of that ratio.
    public static func initialRect(in bounds: CGSize, ratio: CGFloat?) -> CGRect {
        applying(ratio: ratio, to: CGRect(origin: .zero, size: bounds), in: bounds)
    }

    /// Re-shapes `rect` to `ratio` around its centre, keeping it inside `bounds`.
    public static func applying(ratio: CGFloat?, to rect: CGRect, in bounds: CGSize) -> CGRect {
        guard let ratio, ratio > 0, rect.width > 0, rect.height > 0 else { return clamped(rect, in: bounds) }
        var w = rect.width, h = rect.height
        if w / h > ratio { w = h * ratio } else { h = w / ratio }
        let scale = min(1, bounds.width / w, bounds.height / h)
        w *= scale; h *= scale
        return clamped(CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h), in: bounds)
    }

    /// Slides the rect without resizing; it stops at the edges.
    public static func moved(_ rect: CGRect, by delta: CGSize, in bounds: CGSize) -> CGRect {
        clamped(rect.offsetBy(dx: delta.width, dy: delta.height), in: bounds)
    }

    /// Shifts (never resizes) so the rect lies inside `bounds`; oversize rects are cut to fit first.
    public static func clamped(_ rect: CGRect, in bounds: CGSize) -> CGRect {
        let w = min(max(rect.width, 0), bounds.width)
        let h = min(max(rect.height, 0), bounds.height)
        let x = min(max(rect.minX, 0), bounds.width - w)
        let y = min(max(rect.minY, 0), bounds.height - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// The rect after dragging `handle` by `delta` from the state in `rect`.
    public static func dragged(_ rect: CGRect, handle: CropHandle, delta: CGSize, ratio: CGFloat?,
                               in bounds: CGSize, minSize: CGFloat = 8) -> CGRect {
        if handle == .body { return moved(rect, by: delta, in: bounds) }

        let movesLeft = [.topLeft, .left, .bottomLeft].contains(handle)
        let movesRight = [.topRight, .right, .bottomRight].contains(handle)
        let movesTop = [.topLeft, .top, .topRight].contains(handle)
        let movesBottom = [.bottomLeft, .bottom, .bottomRight].contains(handle)

        var l = rect.minX, t = rect.minY, r = rect.maxX, b = rect.maxY
        if movesLeft { l = min(max(l + delta.width, 0), r - minSize) }
        if movesRight { r = max(min(r + delta.width, bounds.width), l + minSize) }
        if movesTop { t = min(max(t + delta.height, 0), b - minSize) }
        if movesBottom { b = max(min(b + delta.height, bounds.height), t + minSize) }

        guard let ratio, ratio > 0 else { return CGRect(x: l, y: t, width: r - l, height: b - t) }

        let isCorner = (movesLeft || movesRight) && (movesTop || movesBottom)
        if isCorner {
            let ax = movesLeft ? rect.maxX : rect.minX   // the fixed, opposite corner
            let ay = movesTop ? rect.maxY : rect.minY
            let mx = movesLeft ? l : r
            let my = movesTop ? t : b
            var w = abs(mx - ax), h = abs(my - ay)
            if w / ratio >= h { h = w / ratio } else { w = h * ratio }
            let maxW = movesLeft ? ax : bounds.width - ax
            let maxH = movesTop ? ay : bounds.height - ay
            let scale = min(1, maxW / max(w, 0.0001), maxH / max(h, 0.0001))
            w *= scale; h *= scale
            if w < minSize { w = minSize; h = w / ratio }
            return CGRect(x: movesLeft ? ax - w : ax, y: movesTop ? ay - h : ay, width: w, height: h)
        }

        if movesLeft || movesRight {
            let fixed = movesLeft ? rect.maxX : rect.minX
            var w = r - l
            var h = w / ratio
            let maxH = 2 * min(rect.midY, bounds.height - rect.midY)
            let maxW = movesLeft ? fixed : bounds.width - fixed
            if h > maxH { h = maxH; w = h * ratio }
            if w > maxW { w = maxW; h = w / ratio }
            return CGRect(x: movesLeft ? fixed - w : fixed, y: rect.midY - h / 2, width: w, height: h)
        }

        let fixed = movesTop ? rect.maxY : rect.minY
        var h = b - t
        var w = h * ratio
        let maxW = 2 * min(rect.midX, bounds.width - rect.midX)
        let maxH = movesTop ? fixed : bounds.height - fixed
        if w > maxW { w = maxW; h = w / ratio }
        if h > maxH { h = maxH; w = h * ratio }
        return CGRect(x: rect.midX - w / 2, y: movesTop ? fixed - h : fixed, width: w, height: h)
    }

    /// Which part of `rect` is under `point`; handles win over the body. Nil outside.
    public static func handle(at point: CGPoint, in rect: CGRect, tolerance: CGFloat = 12) -> CropHandle? {
        let nearL = abs(point.x - rect.minX) <= tolerance
        let nearR = abs(point.x - rect.maxX) <= tolerance
        let nearT = abs(point.y - rect.minY) <= tolerance
        let nearB = abs(point.y - rect.maxY) <= tolerance
        let withinX = point.x >= rect.minX - tolerance && point.x <= rect.maxX + tolerance
        let withinY = point.y >= rect.minY - tolerance && point.y <= rect.maxY + tolerance
        if nearL && nearT { return .topLeft }
        if nearR && nearT { return .topRight }
        if nearL && nearB { return .bottomLeft }
        if nearR && nearB { return .bottomRight }
        if nearT && withinX { return .top }
        if nearB && withinX { return .bottom }
        if nearL && withinY { return .left }
        if nearR && withinY { return .right }
        return rect.contains(point) ? .body : nil
    }

    /// Whole-pixel version of a crop box, inside `bounds`, at least 1x1.
    public static func pixelAligned(_ rect: CGRect, in bounds: CGSize) -> CGRect {
        let x = min(max(rect.minX.rounded(), 0), max(bounds.width - 1, 0))
        let y = min(max(rect.minY.rounded(), 0), max(bounds.height - 1, 0))
        let w = min(max(rect.width.rounded(), 1), bounds.width - x)
        let h = min(max(rect.height.rounded(), 1), bounds.height - y)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

/// Width/height coupling for the resize fields.
public enum ResizeMath {
    public static func height(forWidth width: Int, ratio: CGFloat) -> Int {
        max(1, Int((CGFloat(width) / ratio).rounded()))
    }
    public static func width(forHeight height: Int, ratio: CGFloat) -> Int {
        max(1, Int((CGFloat(height) * ratio).rounded()))
    }
}
