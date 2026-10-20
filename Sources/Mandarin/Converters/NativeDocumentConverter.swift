import AppKit
import UniformTypeIdentifiers

/// RTF, RTFD, DOCX, TXT, and textClipping in; DOCX, TXT, HTML out — all via
/// `NSAttributedString`'s own document import/export (the same text-system
/// machinery TextEdit uses), confirmed by round-tripping real files before
/// writing this. No external tool. Markdown and EPUB aren't reachable this
/// way (`NSAttributedString` doesn't speak either), so those go through
/// `PandocDocumentConverter` instead.
public final class NativeDocumentConverter: Converter {
    private let readableInputs: Set<UTType> = [DocumentFormats.docx, .plainText, .rtf, .rtfd, DocumentFormats.textClipping]
    private let writableOutputs: Set<UTType> = [DocumentFormats.docx, .plainText, .html]

    public init() {}

    public func canConvert(from: UTType, to: UTType) -> Bool {
        readableInputs.contains(from) && writableOutputs.contains(to)
    }

    public func convert(input: URL, output: URL, options: ConversionOptions, progress: @escaping (Double) -> Void) async throws -> ConversionResult {
        progress(0)
        var docAttributes: NSDictionary?
        guard let text = try? NSAttributedString(url: input, options: [:], documentAttributes: &docAttributes) else {
            throw ConversionError.cannotReadInput
        }
        try Task.checkCancellation()
        progress(0.6)

        let outputType = UTType(filenameExtension: output.pathExtension) ?? .data
        let documentType: NSAttributedString.DocumentType
        switch outputType {
        case DocumentFormats.docx: documentType = .officeOpenXML
        case .html: documentType = .html
        default: documentType = .plain
        }

        let range = NSRange(location: 0, length: text.length)
        guard let data = try? text.data(from: range, documentAttributes: [.documentType: documentType]) else {
            throw ConversionError.cannotWriteOutput
        }
        try data.write(to: output)
        progress(1.0)
        return ConversionResult(outputURL: output)
    }
}
