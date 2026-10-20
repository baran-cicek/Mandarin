import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Everything the photo editor can change. Geometry values are in pixels of
/// the *oriented* image (after rotate/flip), top-left origin.
public struct PhotoEdits: Equatable {
    public var quarterTurns = 0                 // clockwise, 0...3
    public var flipHorizontal = false
    public var flipVertical = false
    public var crop: CGRect?                    // nil = whole image
    public var outputSize: CGSize?              // nil = keep size after crop
    public var brightness = 0.0                 // -1...1
    public var contrast = 1.0                   // 0...2
    public var saturation = 1.0                 // 0...2
    public var grayscale = false

    public init() {}

    public var hasColorAdjustments: Bool {
        brightness != 0 || contrast != 1 || saturation != 1 || grayscale
    }

    public var isIdentity: Bool {
        quarterTurns % 4 == 0 && !flipHorizontal && !flipVertical && crop == nil && outputSize == nil && !hasColorAdjustments
    }

    /// Size of the image after rotation (what the crop box lives in).
    public func orientedSize(of original: CGSize) -> CGSize {
        quarterTurns % 2 == 0 ? original : CGSize(width: original.height, height: original.width)
    }
}

public enum PhotoPipeline {
    private static let ciContext = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any])

    /// Rotate by quarter turns (clockwise), then flip, in a single pass.
    public static func oriented(_ image: CGImage, edits: PhotoEdits) throws -> CGImage {
        let turns = ((edits.quarterTurns % 4) + 4) % 4
        if turns == 0 && !edits.flipHorizontal && !edits.flipVertical { return image }
        let w = image.width, h = image.height
        let outW = turns % 2 == 0 ? w : h
        let outH = turns % 2 == 0 ? h : w
        guard let context = makeContext(width: outW, height: outH) else { throw ConversionError.cannotWriteOutput }
        context.translateBy(x: CGFloat(outW) / 2, y: CGFloat(outH) / 2)
        context.scaleBy(x: edits.flipHorizontal ? -1 : 1, y: edits.flipVertical ? -1 : 1)
        context.rotate(by: -CGFloat(turns) * .pi / 2)
        context.draw(image, in: CGRect(x: -CGFloat(w) / 2, y: -CGFloat(h) / 2, width: CGFloat(w), height: CGFloat(h)))
        guard let result = context.makeImage() else { throw ConversionError.cannotWriteOutput }
        return result
    }

    /// Brightness / contrast / saturation / grayscale.
    public static func adjusted(_ image: CGImage, edits: PhotoEdits) throws -> CGImage {
        guard edits.hasColorAdjustments else { return image }
        guard let filter = CIFilter(name: "CIColorControls") else { throw ConversionError.toolFailed("Color adjustment isn't available.") }
        filter.setValue(CIImage(cgImage: image), forKey: kCIInputImageKey)
        filter.setValue(edits.brightness, forKey: kCIInputBrightnessKey)
        filter.setValue(edits.contrast, forKey: kCIInputContrastKey)
        filter.setValue(edits.grayscale ? 0.0 : edits.saturation, forKey: kCIInputSaturationKey)
        guard let output = filter.outputImage,
              let result = ciContext.createCGImage(output, from: CIImage(cgImage: image).extent,
                                                   format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else {
            throw ConversionError.cannotWriteOutput
        }
        return result
    }

    /// What the canvas shows: orientation and colour, no crop or resize.
    public static func preview(of proxy: CGImage, edits: PhotoEdits) throws -> CGImage {
        try adjusted(oriented(proxy, edits: edits), edits: edits)
    }

    /// Full-quality result: orient, crop, colour, resize.
    public static func render(_ full: CGImage, edits: PhotoEdits) throws -> CGImage {
        var image = try oriented(full, edits: edits)
        if let crop = edits.crop {
            let aligned = CropGeometry.pixelAligned(crop, in: CGSize(width: image.width, height: image.height))
            guard let cropped = image.cropping(to: aligned) else { throw ConversionError.toolFailed("Crop area is outside the image.") }
            image = cropped
        }
        image = try adjusted(image, edits: edits)
        if let size = edits.outputSize, Int(size.width) != image.width || Int(size.height) != image.height {
            image = try FileToolImaging.resize(image, width: max(1, Int(size.width)), height: max(1, Int(size.height)))
        }
        return image
    }

    // MARK: - Decoding / encoding

    public static func pixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let orientation = (props[kCGImagePropertyOrientation] as? Int) ?? 1
        return orientation >= 5 ? CGSize(width: h, height: w) : CGSize(width: w, height: h)
    }

    /// Decodes with the EXIF orientation applied, scaled down so the longest
    /// side is at most `maxPixel` (nil = full size).
    public static func decode(_ url: URL, maxPixel: Int? = nil) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw ConversionError.cannotReadInput }
        let longest = maxPixel ?? Int(max(pixelSize(of: url)?.width ?? 0, pixelSize(of: url)?.height ?? 0))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(longest, 1),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw ConversionError.cannotReadInput }
        return image
    }

    /// Writes in `type` when ImageIO can encode it, otherwise as PNG. Returns the real URL.
    @discardableResult
    public static func write(_ image: CGImage, to url: URL, type: UTType, quality: Double = 0.92) throws -> URL {
        var target = url
        var destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
        if destination == nil {
            target = url.deletingPathExtension().appendingPathExtension("png")
            destination = CGImageDestinationCreateWithURL(target as CFURL, UTType.png.identifier as CFString, 1, nil)
        }
        guard let destination else { throw ConversionError.cannotWriteOutput }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: target)
            throw ConversionError.cannotWriteOutput
        }
        return target
    }

    /// Full export of a photo edit as a new copy in `folder`.
    public static func export(source: URL, edits: PhotoEdits, folder: URL) throws -> ConversionResult {
        try Task.checkCancellation()
        let type = (try? source.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? .png
        let full = try decode(source)
        try Task.checkCancellation()
        let result = try render(full, edits: edits)
        try Task.checkCancellation()
        let planned = EditorNaming.outputURL(for: source, in: folder)
        let written = try write(result, to: planned, type: type)
        return ConversionResult(outputURL: written)
    }

    private static func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}
