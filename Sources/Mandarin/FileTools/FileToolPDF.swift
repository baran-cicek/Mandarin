import CoreGraphics
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// PDF-specific helpers for the PDF File Tools.
public enum FileToolPDF {
    /// "Compress" rasterizes every page at a modest DPI and rebuilds the
    /// PDF from those images — genuinely smaller for image-heavy/scanned
    /// PDFs, but the result is no longer text-selectable. Always flagged
    /// "best effort" by the caller; this is a real trade-off, not hidden.
    public static func compress(_ document: PDFDocument, to output: URL) throws {
        guard document.pageCount > 0 else { throw ConversionError.cannotReadInput }
        var images: [CGImage] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index), let image = renderPage(page, dpi: 100) else { continue }
            images.append(image)
        }
        guard !images.isEmpty else { throw ConversionError.cannotReadInput }

        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.pdf.identifier as CFString, images.count, nil) else {
            throw ConversionError.cannotWriteOutput
        }
        for image in images {
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.5] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else {
            throw ConversionError.cannotWriteOutput
        }
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

    /// Parses "1-3,5" style page ranges into sorted, 1-indexed, in-bounds
    /// page numbers.
    public static func parsePageRange(_ text: String, pageCount: Int) -> [Int] {
        var pages: Set<Int> = []
        for part in text.split(separator: ",") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if let dashIndex = trimmed.firstIndex(of: "-") {
                let startString = trimmed[trimmed.startIndex..<dashIndex]
                let endString = trimmed[trimmed.index(after: dashIndex)...]
                if let start = Int(startString), let end = Int(endString), start <= end {
                    for page in start...end where page >= 1 && page <= pageCount {
                        pages.insert(page)
                    }
                }
            } else if let page = Int(trimmed), page >= 1, page <= pageCount {
                pages.insert(page)
            }
        }
        return pages.sorted()
    }
}
