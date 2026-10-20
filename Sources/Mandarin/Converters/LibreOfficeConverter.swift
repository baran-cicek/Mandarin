import Foundation
import PDFKit
import UniformTypeIdentifiers

/// Spreadsheets (XLSX/ODS/XLS/CSV/TSV, and export to PDF) and Slides
/// (PPT/PPTX → PDF/JPG/PNG) via `soffice --headless --convert-to`.
///
/// PDF→PPTX/DOCX/XLSX/EPUB are **not** registered here — verified
/// empirically that LibreOffice's headless PDF import only ever produces a
/// Draw document (its export filters for a PDF-opened file are limited to
/// odg/png/jpg/pdf/html; `--convert-to docx` on a PDF fails with "no
/// export filter"). There's no tool available that can do those routes,
/// so per spec they're left out rather than faked.
///
/// Slide image export goes through PDF first and `PDFRasterizer` second:
/// LibreOffice's own `--convert-to png`/`jpg` silently exports only the
/// first slide of a multi-slide deck (confirmed empirically), while
/// `--convert-to pdf` preserves every slide as its own page.
///
/// Each invocation gets its own temp LibreOffice profile directory
/// (`-env:UserInstallation=`) so concurrent conversions don't fight over
/// the same default profile lock.
public final class LibreOfficeConverter: Converter {
    private let spreadsheetReadable: Set<UTType> = [
        SpreadsheetFormats.xlsx, SpreadsheetFormats.ods, SpreadsheetFormats.xls, .commaSeparatedText, .tabSeparatedText,
    ]
    private let spreadsheetWritable: Set<UTType> = [
        SpreadsheetFormats.xlsx, SpreadsheetFormats.ods, .commaSeparatedText, .tabSeparatedText, .pdf,
    ]
    private let slideReadable: Set<UTType> = [SlideFormats.pptx, SlideFormats.ppt]
    private let slideWritable: Set<UTType> = [.pdf, .jpeg, .png]

    public init() {}

    public func canConvert(from: UTType, to: UTType) -> Bool {
        guard ExternalTool.soffice.isAvailable else { return false }

        if spreadsheetReadable.contains(from) && spreadsheetWritable.contains(to) {
            // CSV<->TSV is handled natively by CSVTSVConverter.
            let isCSVTSVPair = (from == .commaSeparatedText && to == .tabSeparatedText) || (from == .tabSeparatedText && to == .commaSeparatedText)
            return !isCSVTSVPair
        }
        if slideReadable.contains(from) && slideWritable.contains(to) {
            return true
        }
        return false
    }

    public func convert(input: URL, output: URL, options: ConversionOptions, progress: @escaping (Double) -> Void) async throws -> ConversionResult {
        guard let sofficePath = ExternalTool.soffice.path else {
            throw ConversionError.missingTool(name: ExternalTool.soffice.name, installHint: ExternalTool.soffice.installHint)
        }
        progress(0)

        let outputType = UTType(filenameExtension: output.pathExtension) ?? .data
        let inputType = (try? input.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: input.pathExtension) ?? .data
        let isSlideImageExport = slideReadable.contains(inputType) && (outputType == .jpeg || outputType == .png)

        let workDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let intermediateExtension = isSlideImageExport ? "pdf" : FormatCatalog.fileExtension(for: outputType)
        try await runSoffice(sofficePath, convertTo: intermediateExtension, input: input, outDir: workDir)
        try Task.checkCancellation()
        progress(0.7)

        let producedURL = workDir.appendingPathComponent(input.deletingPathExtension().lastPathComponent).appendingPathExtension(intermediateExtension)
        guard FileManager.default.fileExists(atPath: producedURL.path) else {
            throw ConversionError.toolFailed("LibreOffice didn't produce an output file for this conversion.")
        }

        if isSlideImageExport {
            guard let document = PDFDocument(url: producedURL) else {
                throw ConversionError.cannotReadInput
            }
            let resultURL = try PDFRasterizer.rasterize(document, outputType: outputType, plannedOutputURL: output, quality: options.quality)
            progress(1.0)
            return ConversionResult(outputURL: resultURL, warning: "Best effort — layout may not match the original exactly")
        }

        try FileManager.default.moveItem(at: producedURL, to: output)
        progress(1.0)
        let warning = slideReadable.contains(inputType) ? "Best effort — layout may not match the original exactly" : nil
        return ConversionResult(outputURL: output, warning: warning)
    }

    private func runSoffice(_ sofficePath: String, convertTo targetExtension: String, input: URL, outDir: URL) async throws {
        let profileDir = outDir.appendingPathComponent("profile")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sofficePath)
        process.arguments = [
            "--headless", "--norestore",
            "-env:UserInstallation=file://\(profileDir.path)",
            "--convert-to", targetExtension,
            "--outdir", outDir.path,
            input.path,
        ]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        try process.run()

        await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                process.terminationHandler = { _ in continuation.resume() }
            }
        }, onCancel: {
            process.terminate()
        })

        if Task.isCancelled {
            throw CancellationError()
        }

        guard process.terminationStatus == 0 else {
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let message = Self.cleanedMessage(from: data)
            throw ConversionError.toolFailed(fromRawOutput: message ?? "LibreOffice conversion failed.")
        }

        // soffice can report "no export filter" with exit code 0, so check
        // its own output, not just the exit status.
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        if let message = Self.cleanedMessage(from: data), message.contains("Error:") {
            throw ConversionError.toolFailed(fromRawOutput: message)
        }
    }

    /// soffice's stdout/stderr is full of harmless "Fontconfig warning"
    /// noise that would otherwise bury the one line a user actually needs.
    private static func cleanedMessage(from data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let message = text
            .split(separator: "\n")
            .filter { !$0.contains("Fontconfig warning") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? nil : message
    }
}

enum SlideFormats {
    static let pptx = UTType.known(nil, ext: "pptx")
    static let ppt = UTType.known(nil, ext: "ppt")
}
