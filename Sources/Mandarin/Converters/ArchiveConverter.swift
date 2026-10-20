import Foundation
import UniformTypeIdentifiers

/// Archive↔archive re-packing: every route extracts the input with `unar`
/// (handles zip/tar/gzip/rar alike) and repacks the contents with the
/// system's own `/usr/bin/zip`/`tar`/`gzip` (always present on macOS, not
/// a Homebrew dependency that can be missing) — "convert zip to tar"
/// means re-archiving its *contents*, not wrapping the whole zip file
/// inside a tar. Deliberately archive-to-archive *only* — a universal
/// "compress any file" action would add 3 targets to every single file
/// type's Convert wheel, which is exactly the "more than 8 targets"
/// crowding the spec asks to avoid, and "compress this" is really a File
/// Tool (Milestone 7), not a format conversion.
public final class ArchiveConverter: Converter {
    public init() {}

    public func canConvert(from: UTType, to: UTType) -> Bool {
        guard ArchiveFormats.isArchiveOutputType(to), from != to else { return false }
        let isArchiveInput = ArchiveFormats.isArchiveOutputType(from) || from == ArchiveFormats.rar
        return isArchiveInput && ExternalTool.unar.isAvailable
    }

    public func convert(input: URL, output: URL, options: ConversionOptions, progress: @escaping (Double) -> Void) async throws -> ConversionResult {
        progress(0)
        let outputType = UTType(filenameExtension: output.pathExtension) ?? .data

        // The input is itself an archive — "convert zip to tar" means
        // re-archiving its *contents*, not wrapping the whole zip file
        // inside a tar. `unar` extracts zip/tar/gzip/rar alike.
        let extractedDir = try await extractArchive(input)
        defer { try? FileManager.default.removeItem(at: extractedDir) }
        try Task.checkCancellation()
        progress(0.5)
        let rawItems = try FileManager.default.contentsOfDirectory(at: extractedDir, includingPropertiesForKeys: nil)
        let items = Self.flattenSingleWrapperFolder(rawItems)
        guard !items.isEmpty else {
            throw ConversionError.toolFailed("This archive appears to be empty.")
        }

        let finalOutputURL = try await pack(items: items, into: output, format: outputType)
        progress(1.0)
        return ConversionResult(outputURL: finalOutputURL)
    }

    /// Packs `items` into `format`. Returns the URL actually written —
    /// multiple items being gzipped need a real tar+gzip, so that case is
    /// named `.tar.gz` (not the originally-planned bare `.gz`, which would
    /// misdescribe the format) and the real path comes back here, same
    /// pattern as the multi-page PDF/slide image folder case.
    private func pack(items: [URL], into output: URL, format: UTType) async throws -> URL {
        let parent = commonParent(of: items)
        let workingDir = try parent ?? stageCopies(of: items)
        defer { if parent == nil { try? FileManager.default.removeItem(at: workingDir) } }
        let names = items.map(\.lastPathComponent)

        if format == ArchiveFormats.gzip, items.count == 1,
           (try? items[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true {
            try await gzipSingleFile(items[0], to: output)
            return output
        }

        switch format {
        case .zip:
            try await ProcessRunner.run("/usr/bin/zip", arguments: ["-r", "-q", output.path] + names, currentDirectory: workingDir)
            return output
        case ArchiveFormats.tar:
            try await ProcessRunner.run("/usr/bin/tar", arguments: ["-cf", output.path, "-C", workingDir.path] + names)
            return output
        case ArchiveFormats.gzip:
            let tarGzURL = Self.nonClobberingRenamed(output, extension: "tar.gz")
            try await ProcessRunner.run("/usr/bin/tar", arguments: ["-czf", tarGzURL.path, "-C", workingDir.path] + names)
            return tarGzURL
        default:
            throw ConversionError.unsupportedRoute("Unknown archive format.")
        }
    }

    private static func nonClobberingRenamed(_ url: URL, extension newExtension: String) -> URL {
        let folder = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        var candidate = folder.appendingPathComponent(base).appendingPathExtension(newExtension)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(counter)").appendingPathExtension(newExtension)
            counter += 1
        }
        return candidate
    }

    private func stageCopies(of items: [URL]) throws -> URL {
        let stagingDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        for item in items {
            try FileManager.default.copyItem(at: item, to: stagingDir.appendingPathComponent(item.lastPathComponent))
        }
        return stagingDir
    }

    /// `unar` always extracts into a subfolder named after the archive
    /// (even when the archive's own contents were loose top-level files),
    /// so a re-archive would otherwise wrap everything one level deeper
    /// than the original. Descend into that one wrapper folder if that's
    /// all `unar` produced.
    private static func flattenSingleWrapperFolder(_ items: [URL]) -> [URL] {
        guard items.count == 1,
              (try? items[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
              let nested = try? FileManager.default.contentsOfDirectory(at: items[0], includingPropertiesForKeys: nil),
              !nested.isEmpty else {
            return items
        }
        return nested
    }

    private func commonParent(of items: [URL]) -> URL? {
        guard let first = items.first?.deletingLastPathComponent().standardizedFileURL else { return nil }
        return items.allSatisfy { $0.deletingLastPathComponent().standardizedFileURL == first } ? first : nil
    }

    private func extractArchive(_ input: URL) async throws -> URL {
        guard let unarPath = ExternalTool.unar.path else {
            throw ConversionError.missingTool(name: ExternalTool.unar.name, installHint: ExternalTool.unar.installHint)
        }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try await ProcessRunner.run(unarPath, arguments: ["-o", destination.path, input.path])
        return destination
    }

    private func gzipSingleFile(_ input: URL, to output: URL) async throws {
        guard FileManager.default.createFile(atPath: output.path, contents: nil) else {
            throw ConversionError.cannotWriteOutput
        }
        let outputHandle = try FileHandle(forWritingTo: output)
        defer { try? outputHandle.close() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-c", input.path]
        process.standardOutput = outputHandle
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()

        await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                process.terminationHandler = { _ in continuation.resume() }
            }
        }, onCancel: {
            process.terminate()
        })

        if Task.isCancelled { throw CancellationError() }
        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ConversionError.toolFailed(fromRawOutput: message ?? "gzip failed.")
        }
    }

}
