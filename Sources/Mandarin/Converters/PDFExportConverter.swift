import Foundation
import PDFKit
import UniformTypeIdentifiers

/// What Mandarin can actually do with a PDF, natively, no external tool:
/// render pages to JPG/PNG at 300 DPI (via `PDFRasterizer`), or extract
/// text to TXT/MD. PDF→DOCX/PPTX/XLSX/EPUB/PAGES are **not** offered —
/// LibreOffice's headless PDF import only ever produces a Draw document
/// (export filters exist for odg/png/jpg/pdf/html only, verified
/// empirically; see PROGRESS.md), and pandoc has no PDF reader at all.
/// There's no tool on this Mac that can actually do those routes, so
/// rather than fake a bad result, they're simply not registered.
public final class PDFExportConverter: Converter {
    public init() {}

    public func canConvert(from: UTType, to: UTType) -> Bool {
        guard from == .pdf else { return false }
        return to == .jpeg || to == .png || to == .plainText || to == DocumentFormats.markdown
    }

    public func convert(input: URL, output: URL, options: ConversionOptions, progress: @escaping (Double) -> Void) async throws -> ConversionResult {
        progress(0)
        guard let document = PDFDocument(url: input), document.pageCount > 0 else {
            throw ConversionError.cannotReadInput
        }

        let outputType = UTType(filenameExtension: output.pathExtension) ?? .data

        if outputType == .jpeg || outputType == .png {
            let resultURL = try PDFRasterizer.rasterize(document, outputType: outputType, plannedOutputURL: output, quality: options.quality)
            progress(1.0)
            return ConversionResult(outputURL: resultURL)
        }

        // TXT/MD: extract each page's text natively via PDFKit.
        var pages: [String] = []
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            pages.append(document.page(at: index)?.string ?? "")
            progress(Double(index + 1) / Double(document.pageCount) * 0.9)
        }
        let text = pages.joined(separator: "\n\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConversionError.toolFailed("This PDF has no extractable text (it may be a scan of images).")
        }
        try text.write(to: output, atomically: true, encoding: .utf8)
        progress(1.0)

        if outputType == DocumentFormats.markdown {
            return ConversionResult(outputURL: output, warning: "Best effort — plain text only, no headings or formatting")
        }
        return ConversionResult(outputURL: output)
    }
}
