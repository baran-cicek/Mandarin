import Foundation

/// Runs a process with cancellation support, capturing combined stdout+
/// stderr for the error message on failure. Used by `FileToolRunner`;
/// `FFmpegMediaConverter`/`LibreOfficeConverter`/`ArchiveConverter` predate
/// this and have their own near-identical copies — left alone rather than
/// risk regressing already-tested code for a pure refactor.
enum ProcessRunner {
    @discardableResult
    static func run(_ executable: String, arguments: [String], currentDirectory: URL? = nil) async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = URL(fileURLWithPath: executable).lastPathComponent == "ffmpeg" ? ExternalTool.ffmpegArguments(arguments) : arguments
        process.standardInput = FileHandle.nullDevice
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()

        await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                process.terminationHandler = { _ in continuation.resume() }
            }
        }, onCancel: {
            process.terminate()
        })

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if Task.isCancelled { throw CancellationError() }
        guard process.terminationStatus == 0 else {
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ConversionError.toolFailed(fromRawOutput: message ?? "\(executable) failed.")
        }
        return data
    }
}
