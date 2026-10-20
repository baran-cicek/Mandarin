import Foundation
import UniformTypeIdentifiers

/// Markdown and EPUB — the two Documents formats `NSAttributedString`
/// can't read or write — via `pandoc`, letting it infer both the reader
/// and writer purely from the input/output file extensions (confirmed
/// manually: `pandoc in.md -o out.epub`, `pandoc in.epub -o out.docx`,
/// `pandoc in.rtf -o out.md` all just work with no explicit `-f`/`-t`).
/// Only engaged when Markdown or EPUB is actually on one side — RTF/DOCX/
/// TXT/HTML among themselves stay on `NativeDocumentConverter`.
public final class PandocDocumentConverter: Converter {
    private let readable: Set<UTType> = [DocumentFormats.docx, .plainText, .rtf, .html, .epub, DocumentFormats.markdown]
    private let writable: Set<UTType> = [DocumentFormats.docx, .plainText, .html, .epub, DocumentFormats.markdown]

    public init() {}

    public func canConvert(from: UTType, to: UTType) -> Bool {
        guard ExternalTool.pandoc.isAvailable else { return false }
        guard readable.contains(from), writable.contains(to) else { return false }
        return from == DocumentFormats.markdown || from == .epub || to == DocumentFormats.markdown || to == .epub
    }

    public func convert(input: URL, output: URL, options: ConversionOptions, progress: @escaping (Double) -> Void) async throws -> ConversionResult {
        guard let pandocPath = ExternalTool.pandoc.path else {
            throw ConversionError.missingTool(name: ExternalTool.pandoc.name, installHint: ExternalTool.pandoc.installHint)
        }
        progress(0)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pandocPath)
        process.arguments = [input.path, "-o", output.path]
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        try process.run()

        await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                process.terminationHandler = { _ in continuation.resume() }
            }
        }, onCancel: {
            process.terminate()
        })

        if Task.isCancelled {
            try? FileManager.default.removeItem(at: output)
            throw CancellationError()
        }

        guard process.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: output)
            let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ConversionError.toolFailed(fromRawOutput: message ?? "pandoc failed.")
        }

        progress(1.0)

        let outputType = UTType(filenameExtension: output.pathExtension) ?? .data
        let inputType = (try? input.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: input.pathExtension) ?? .data
        let lossy = [outputType, inputType].contains(.epub) || [outputType, inputType].contains(DocumentFormats.docx)
        return ConversionResult(outputURL: output, warning: lossy ? "Best effort — formatting may not carry over perfectly" : nil)
    }
}
