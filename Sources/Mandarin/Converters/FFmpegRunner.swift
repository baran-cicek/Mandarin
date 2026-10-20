import Foundation

/// Runs ffmpeg with `-progress pipe:1`, reporting 0...1 progress, honouring
/// cancellation and removing a partial output on failure.
enum FFmpegRunner {
    static func run(ffmpegPath: String, arguments: [String], totalDuration: Double?, output: URL, progress: @escaping (Double) -> Void) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = ExternalTool.ffmpegArguments(arguments)
        process.standardInput = FileHandle.nullDevice
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()

        let progressTask: Task<Void, Never>? = totalDuration.map { duration in
            Task {
                do {
                    for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
                        guard line.hasPrefix("out_time_us="), duration > 0 else { continue }
                        if let micros = Double(line.dropFirst("out_time_us=".count)) {
                            progress(min(1.0, max(0, micros / 1_000_000 / duration)))
                        }
                    }
                } catch {}
            }
        }

        await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                process.terminationHandler = { _ in continuation.resume() }
            }
        }, onCancel: {
            process.terminate()
        })
        progressTask?.cancel()

        if Task.isCancelled {
            try? FileManager.default.removeItem(at: output)
            throw CancellationError()
        }
        guard process.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: output)
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ConversionError.toolFailed(fromRawOutput: message ?? "ffmpeg failed.")
        }
        progress(1.0)
    }
}
