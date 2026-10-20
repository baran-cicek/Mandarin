import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

public struct RGB: Equatable {
    public var r: Double, g: Double, b: Double      // 0...1, sRGB
    public init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }
    public static let white = RGB(r: 1, g: 1, b: 1)
    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: 1) }
}

public enum BackgroundRemoval: Equatable {
    case none
    /// Makes pixels close to `key` transparent. `tolerance` 0...1; `contiguous` limits it to areas touching the border.
    case solidColor(key: RGB, tolerance: Double, contiguous: Bool)
    /// Vision foreground mask (macOS 14+).
    case subject
}

public enum BackgroundFill: Equatable {
    case none
    case solid(RGB)
    case gradient(from: RGB, to: RGB, angleDegrees: Double)
}

public struct BackgroundEdit: Equatable {
    public var removal: BackgroundRemoval = .none
    public var fill: BackgroundFill = .none
    public init(removal: BackgroundRemoval = .none, fill: BackgroundFill = .none) { self.removal = removal; self.fill = fill }
}

public enum BackgroundTool {
    public static var subjectMaskAvailable: Bool {
        if #available(macOS 14.0, *) { return true }
        return false
    }

    // MARK: Pixel access

    private static func rgbaBuffer(_ image: CGImage) throws -> (data: [UInt8], width: Int, height: Int) {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ok = data.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { throw ConversionError.cannotReadInput }
        return (data, w, h)
    }

    private static func makeImage(_ data: [UInt8], width: Int, height: Int) throws -> CGImage {
        var copy = data
        let image: CGImage? = copy.withUnsafeMutableBytes { raw in
            CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
        guard let image else { throw ConversionError.cannotWriteOutput }
        return image
    }

    /// Average of the four corner pixels: a good guess for a studio-style background.
    public static func guessBackgroundColor(_ image: CGImage) throws -> RGB {
        let (data, w, h) = try rgbaBuffer(image)
        var r = 0.0, g = 0.0, b = 0.0
        for (x, y) in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)] {
            let i = (y * w + x) * 4
            let a = max(Double(data[i + 3]), 1)
            r += Double(data[i]) / a; g += Double(data[i + 1]) / a; b += Double(data[i + 2]) / a
        }
        return RGB(r: r / 4, g: g / 4, b: b / 4)
    }

    public static func color(at point: CGPoint, in image: CGImage) -> RGB? {
        guard let (data, w, h) = try? rgbaBuffer(image) else { return nil }
        let x = min(max(Int(point.x), 0), w - 1), y = min(max(Int(point.y), 0), h - 1)
        let i = (y * w + x) * 4
        let a = max(Double(data[i + 3]), 1)
        return RGB(r: min(Double(data[i]) / a, 1), g: min(Double(data[i + 1]) / a, 1), b: min(Double(data[i + 2]) / a, 1))
    }

    // MARK: Removal

    /// Makes pixels within `tolerance` of `key` transparent, with a soft edge.
    public static func removeSolidColor(_ image: CGImage, key: RGB, tolerance: Double, contiguous: Bool) throws -> CGImage {
        var (data, w, h) = try rgbaBuffer(image)
        let tol = min(max(tolerance, 0), 1)
        let soft = 0.06
        let scale = 1.0 / 3.0.squareRoot()

        func distance(_ i: Int) -> Double {
            let a = Double(data[i + 3])
            guard a > 0 else { return 0 }
            let dr = Double(data[i]) / a - key.r, dg = Double(data[i + 1]) / a - key.g, db = Double(data[i + 2]) / a - key.b
            return (dr * dr + dg * dg + db * db).squareRoot() * scale
        }

        var candidate = [Bool](repeating: false, count: w * h)
        if contiguous {
            var stack: [Int] = []
            func push(_ p: Int) { if !candidate[p], distance(p * 4) <= tol + soft { candidate[p] = true; stack.append(p) } }
            for x in 0..<w { push(x); push((h - 1) * w + x) }
            for y in 0..<h { push(y * w); push(y * w + w - 1) }
            var steps = 0
            while let p = stack.popLast() {
                steps += 1
                if steps % 200_000 == 0 { try Task.checkCancellation() }
                let x = p % w, y = p / w
                if x > 0 { push(p - 1) }
                if x < w - 1 { push(p + 1) }
                if y > 0 { push(p - w) }
                if y < h - 1 { push(p + w) }
            }
        } else {
            for p in 0..<(w * h) { candidate[p] = true }
        }

        for p in 0..<(w * h) where candidate[p] {
            if p % 500_000 == 0 { try Task.checkCancellation() }
            let i = p * 4
            let d = distance(i)
            let keep: Double = d <= tol ? 0 : (d >= tol + soft ? 1 : (d - tol) / soft)
            if keep < 1 {
                for c in 0..<4 { data[i + c] = UInt8((Double(data[i + c]) * keep).rounded()) }
            }
        }
        return try makeImage(data, width: w, height: h)
    }

    /// Cuts out the foreground subject using Vision. Returns nil when Vision finds no subject.
    public static func removeSubject(_ image: CGImage) throws -> CGImage? {
        guard #available(macOS 14.0, *) else { throw ConversionError.unsupportedRoute("Subject detection needs macOS 14 or later.") }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else { return nil }
        let buffer = try observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: false)
        let ci = CIImage(cvPixelBuffer: buffer)
        return CIContext().createCGImage(ci, from: ci.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }

    // MARK: Fill

    public static func composite(_ image: CGImage, fill: BackgroundFill) throws -> CGImage {
        let w = image.width, h = image.height
        guard fill != .none else { return image }
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ConversionError.cannotWriteOutput }
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        switch fill {
        case .none: break
        case .solid(let color):
            context.setFillColor(color.cgColor)
            context.fill(rect)
        case .gradient(let from, let to, let angle):
            let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [from.cgColor, to.cgColor] as CFArray, locations: [0, 1])!
            // Angle 0 = left to right, 90 = top to bottom (screen sense).
            let radians = angle * .pi / 180
            let dx = cos(radians), dy = -sin(radians) * -1       // screen y grows downward
            let half = CGFloat(abs(dx) * Double(w) + abs(dy) * Double(h)) / 2
            let centre = CGPoint(x: CGFloat(w) / 2, y: CGFloat(h) / 2)
            let start = CGPoint(x: centre.x - CGFloat(dx) * half, y: centre.y + CGFloat(dy) * half)
            let end = CGPoint(x: centre.x + CGFloat(dx) * half, y: centre.y - CGFloat(dy) * half)
            context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        context.draw(image, in: rect)
        guard let result = context.makeImage() else { throw ConversionError.cannotWriteOutput }
        return result
    }

    // MARK: Pipeline

    public static func apply(_ edit: BackgroundEdit, to image: CGImage) throws -> CGImage {
        var result = image
        switch edit.removal {
        case .none: break
        case .solidColor(let key, let tolerance, let contiguous):
            result = try removeSolidColor(result, key: key, tolerance: tolerance, contiguous: contiguous)
        case .subject:
            guard let cut = try removeSubject(result) else { throw ConversionError.toolFailed("No foreground subject found in this image.") }
            result = cut
        }
        try Task.checkCancellation()
        return try composite(result, fill: edit.fill)
    }

    public static func export(source: URL, edit: BackgroundEdit, folder: URL) throws -> ConversionResult {
        let image = try PhotoPipeline.decode(source)
        let result = try apply(edit, to: image)
        try Task.checkCancellation()
        let output = EditorNaming.outputURL(for: source, suffix: "background", extension: "png", in: folder)
        try PhotoPipeline.write(result, to: output, type: .png)
        return ConversionResult(outputURL: output)
    }
}
