import Foundation
import UniformTypeIdentifiers

/// Handles every audio/video format AVFoundation can't reliably produce
/// (see `MediaFormats.Format.engine`) by shelling out to `ffmpeg`. Progress
/// comes from `ffmpeg -progress pipe:1`'s machine-readable `out_time_us=`
/// lines against the input's duration (via `ffprobe`); cancellation
/// terminates the process and deletes whatever partial file it left.
///
/// Letting ffmpeg pick its own default codec for a given output extension
/// works correctly for every format here *except* two: GIF needs an
/// explicit fps/scale filter (the unfiltered default is enormous and far
/// too slow), and OGG defaults to FLAC-in-Ogg instead of the conventional
/// Vorbis-in-Ogg. Everything else — MP3, WAV, FLAC, Opus, AIFF, WMA, MKV,
/// WebM, AVI, WMV, and audio-extraction-from-video (`-vn`) — needs no
/// override at all.
///
/// Video→audio is deliberately MP3-only (not "any audio format"): the
/// spec asks for "extract MP3," and letting every video also offer
/// WAV/FLAC/Opus/AIFF/WMA/OGG extraction pushed a dragged MP4 past 13
/// Convert-wheel targets — exactly the crowding the spec's "more than 8
/// targets" rule asks to avoid, caught by a self-test, not by guessing.
/// `AVFoundationMediaConverter` separately offers M4A extraction, which is
/// a distinctly justified, reliable native route, not part of this list.
public final class FFmpegMediaConverter: Converter {
    public init() {}

    public func canConvert(from: UTType, to: UTType) -> Bool {
        guard ExternalTool.ffmpeg.isAvailable else { return false }
        guard let toFormat = MediaFormats.format(for: to), toFormat.engine == .ffmpeg else { return false }
        guard let fromFormat = MediaFormats.format(for: from) else { return false }
        if fromFormat.domain == .video && toFormat.domain == .audio {
            return to == .mp3
        }
        return !(fromFormat.domain == .audio && toFormat.domain == .video)
    }

    public func convert(input: URL, output: URL, options: ConversionOptions, progress: @escaping (Double) -> Void) async throws -> ConversionResult {
        guard let ffmpegPath = ExternalTool.ffmpeg.path else {
            throw ConversionError.missingTool(name: ExternalTool.ffmpeg.name, installHint: ExternalTool.ffmpeg.installHint)
        }

        let inputType = (try? input.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: input.pathExtension) ?? .data
        let outputType = UTType(filenameExtension: output.pathExtension) ?? .data
        let inputIsVideo = MediaFormats.format(for: inputType)?.domain == .video
        let outputIsAudio = MediaFormats.format(for: outputType)?.domain == .audio

        var args = ["-y", "-i", input.path]
        if inputIsVideo && outputIsAudio {
            args.append("-vn")
        }
        if outputType == .gif {
            args += ["-vf", "fps=10,scale=480:-1:flags=lanczos"]
        }
        if outputType == MediaFormats.ogg {
            // This Homebrew ffmpeg build only has the native "vorbis"
            // encoder (no libvorbis), which is marked experimental and
            // stereo-only — without these flags ffmpeg's bare ".ogg"
            // default is FLAC-in-Ogg, not the conventional Vorbis-in-Ogg.
            args += ["-c:a", "vorbis", "-strict", "-2", "-ac", "2", "-q:a", "5"]
        }
        args += ["-progress", "pipe:1", "-loglevel", "error", output.path]

        let totalDuration = Self.probeDuration(of: input)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = ExternalTool.ffmpegArguments(args)
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
                } catch {
                    // Stream just closes when the process exits — not an error for us.
                }
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
            let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ConversionError.toolFailed(fromRawOutput: message ?? "ffmpeg failed.")
        }

        progress(1.0)
        return ConversionResult(outputURL: output)
    }

    private static func probeDuration(of url: URL) -> Double? {
        guard let ffprobePath = ExternalTool.ffprobe.path else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobePath)
        process.arguments = ["-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", url.path]
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let string = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return Double(string)
    }
}
