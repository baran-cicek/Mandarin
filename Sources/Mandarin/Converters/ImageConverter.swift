import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Handles the whole image family (JPG, PNG, WebP, HEIC, TIFF, AVIF, BMP),
/// PDF export, and SVG input, as one converter: loading a `CGImage` has at
/// most two sources (native ImageIO, or SVG-via-NSImage), and writing one
/// has at most two destinations (native ImageIO, or WebP-via-`cwebp`), so
/// splitting this into one type per format would just be the same two
/// branches copy-pasted eight times.
///
/// Native ImageIO support is detected at runtime (`CGImageSourceCopyTypeIdentifiers`
/// / `CGImageDestinationCopyTypeIdentifiers`) rather than assumed, since it
/// varies across macOS versions — a format silently missing on an older OS
/// is simply not offered, instead of crashing.
public final class ImageConverter: Converter {
    private let readableTypes: Set<UTType>
    private let writableTypes: Set<UTType>

    public init() {
        let sourceIDs = (CGImageSourceCopyTypeIdentifiers() as? [String]) ?? []
        let destIDs = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
        let knownTypes = ImageFormats.outputs.map(\.type)

        readableTypes = Set(knownTypes.filter { sourceIDs.contains($0.identifier) }).union([.svg])
        writableTypes = Set(knownTypes.filter { destIDs.contains($0.identifier) }).union(
            ExternalTool.cwebp.isAvailable ? [ImageFormats.webp] : []
        )
    }

    public func canConvert(from: UTType, to: UTType) -> Bool {
        readableTypes.contains(from) && writableTypes.contains(to)
    }

    public func convert(input: URL, output: URL, options: ConversionOptions, progress: @escaping (Double) -> Void) async throws -> ConversionResult {
        progress(0)
        let cgImage = try loadCGImage(from: input)
        try Task.checkCancellation()
        progress(0.5)

        guard let outputType = UTType(filenameExtension: output.pathExtension) else {
            throw ConversionError.cannotWriteOutput
        }

        if outputType == ImageFormats.webp {
            try writeWebP(cgImage, to: output, quality: options.quality)
        } else {
            try writeNative(cgImage, to: output, type: outputType, quality: options.quality)
        }
        progress(1.0)
        return ConversionResult(outputURL: output)
    }

    private func loadCGImage(from url: URL) throws -> CGImage {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? UTType(filenameExtension: url.pathExtension)
        if type == .svg {
            return try rasterizeSVG(url)
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ConversionError.cannotReadInput
        }
        return image
    }

    private func rasterizeSVG(_ url: URL) throws -> CGImage {
        guard let nsImage = NSImage(contentsOf: url), nsImage.size.width > 0, nsImage.size.height > 0 else {
            throw ConversionError.cannotReadInput
        }
        let scale: CGFloat = 4
        let pixelSize = NSSize(width: nsImage.size.width * scale, height: nsImage.size.height * scale)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pixelSize.width),
            pixelsHigh: Int(pixelSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw ConversionError.cannotReadInput
        }
        rep.size = pixelSize

        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            throw ConversionError.cannotReadInput
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        nsImage.draw(in: NSRect(origin: .zero, size: pixelSize))
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = rep.cgImage else {
            throw ConversionError.cannotReadInput
        }
        return cgImage
    }

    private func writeNative(_ image: CGImage, to url: URL, type: UTType, quality: Double) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw ConversionError.cannotWriteOutput
        }
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ConversionError.cannotWriteOutput
        }
    }

    private func writeWebP(_ image: CGImage, to url: URL, quality: Double) throws {
        guard let cwebpPath = ExternalTool.cwebp.path else {
            throw ConversionError.missingTool(name: ExternalTool.cwebp.name, installHint: ExternalTool.cwebp.installHint)
        }

        let tempPNG = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: tempPNG) }
        try writeNative(image, to: tempPNG, type: .png, quality: 1.0)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cwebpPath)
        process.arguments = ["-quiet", "-q", String(Int(quality * 100)), tempPNG.path, "-o", url.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ConversionError.toolFailed(fromRawOutput: message ?? "cwebp failed.")
        }
    }
}
