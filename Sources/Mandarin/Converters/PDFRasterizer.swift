import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Renders PDF pages to images, natively (PDFKit + CoreGraphics, no
/// external tool). Shared by PDF→JPG/PNG and, via an intermediate PDF,
/// PPT/PPTX→JPG/PNG — LibreOffice's own `--convert-to png/jpg` silently
/// exports only the first slide/page of a multi-page document, so neither
/// route uses it for images.
enum PDFRasterizer {
    /// A single page writes `plannedOutputURL` directly; more than one
    /// writes `name-1.ext`, `name-2.ext`, ... into a new sibling folder
    /// (never loose numbered files next to other output), returning that
    /// folder instead.
    static func rasterize(_ document: PDFDocument, outputType: UTType, plannedOutputURL: URL, dpi: CGFloat = 300, quality: Double) throws -> URL {
        let pageCount = document.pageCount
        guard pageCount > 0 else { throw ConversionError.cannotReadInput }

        if pageCount == 1 {
            guard let page = document.page(at: 0), let image = renderPage(page, dpi: dpi) else {
                throw ConversionError.cannotReadInput
            }
            try write(image, to: plannedOutputURL, type: outputType, quality: quality)
            return plannedOutputURL
        }

        let destinationFolder = plannedOutputURL.deletingLastPathComponent()
        let baseName = plannedOutputURL.deletingPathExtension().lastPathComponent
        let folderURL = OutputPathPlanner.nonClobberingFolder(named: baseName, in: destinationFolder)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let extensionString = FormatCatalog.fileExtension(for: outputType)
        let digits = String(pageCount).count
        for index in 0..<pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index), let image = renderPage(page, dpi: dpi) else { continue }
            let pageNumber = String(format: "%0\(digits)d", index + 1)
            let pageURL = folderURL.appendingPathComponent("\(baseName)-\(pageNumber)").appendingPathExtension(extensionString)
            try write(image, to: pageURL, type: outputType, quality: quality)
        }
        return folderURL
    }

    private static func renderPage(_ page: PDFPage, dpi: CGFloat) -> CGImage? {
        let mediaBox = page.bounds(for: .mediaBox)
        guard mediaBox.width > 0, mediaBox.height > 0 else { return nil }
        let scale = dpi / 72.0
        let width = max(1, Int(mediaBox.width * scale))
        let height = max(1, Int(mediaBox.height * scale))

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height,
                  bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        context.setFillColor(CGColor.white)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -mediaBox.origin.x, y: -mediaBox.origin.y)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }

    private static func write(_ image: CGImage, to url: URL, type: UTType, quality: Double) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw ConversionError.cannotWriteOutput
        }
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ConversionError.cannotWriteOutput
        }
    }
}
