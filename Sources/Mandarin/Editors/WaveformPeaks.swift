import AVFoundation
import Foundation

/// Folds a stream of samples into a fixed number of peak buckets (max |sample|
/// per bucket), so a long file never has to be held in memory.
public struct PeakAccumulator {
    public private(set) var peaks: [Float]
    private let totalFrames: Int
    private var position = 0

    public init(bucketCount: Int, totalFrames: Int) {
        peaks = [Float](repeating: 0, count: max(bucketCount, 1))
        self.totalFrames = max(totalFrames, 1)
    }

    public var framesSeen: Int { position }

    /// Adds mono samples (or already max-combined channels).
    public mutating func add(_ samples: UnsafeBufferPointer<Float>) {
        let buckets = peaks.count
        for sample in samples {
            let bucket = min(position * buckets / totalFrames, buckets - 1)
            let value = abs(sample)
            if value > peaks[bucket] { peaks[bucket] = value }
            position += 1
        }
    }

    public mutating func add(_ samples: [Float]) {
        samples.withUnsafeBufferPointer { add($0) }
    }
}

public enum WaveformLoader {
    /// Streams `url` and returns `bucketCount` peaks in 0...1. `partial` is
    /// called now and then with the peaks so far (not on the main thread).
    /// Uses AVAudioFile where it can read the file, ffmpeg otherwise.
    public static func load(_ url: URL, bucketCount: Int, partial: @escaping @Sendable ([Float]) -> Void = { _ in }) async throws -> [Float] {
        if let peaks = try readWithAVAudioFile(url, bucketCount: bucketCount, partial: partial) { return peaks }
        return try await readWithFFmpeg(url, bucketCount: bucketCount, partial: partial)
    }

    private static func readWithAVAudioFile(_ url: URL, bucketCount: Int, partial: @Sendable ([Float]) -> Void) throws -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false),
              file.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 65_536) else { return nil }
        var accumulator = PeakAccumulator(bucketCount: bucketCount, totalFrames: Int(file.length))
        var lastReport = Date()
        var mono = [Float](repeating: 0, count: 65_536)
        while file.framePosition < file.length {
            try Task.checkCancellation()
            try file.read(into: buffer, frameCount: 65_536)
            let frames = Int(buffer.frameLength)
            if frames == 0 { break }
            guard let channels = buffer.floatChannelData else { return nil }
            for i in 0..<frames { mono[i] = 0 }
            for c in 0..<Int(buffer.format.channelCount) {
                let samples = channels[c]
                for i in 0..<frames { mono[i] = max(mono[i], abs(samples[i])) }
            }
            mono.withUnsafeBufferPointer { accumulator.add(UnsafeBufferPointer(rebasing: $0[0..<frames])) }
            if Date().timeIntervalSince(lastReport) > 0.1 { partial(accumulator.peaks); lastReport = Date() }
        }
        return accumulator.peaks
    }

    private static func readWithFFmpeg(_ url: URL, bucketCount: Int, partial: @Sendable ([Float]) -> Void) async throws -> [Float] {
        guard let ffmpeg = ExternalTool.ffmpeg.path else {
            throw ConversionError.missingTool(name: ExternalTool.ffmpeg.name, installHint: ExternalTool.ffmpeg.installHint)
        }
        let rate = 8000
        let duration = FileToolMediaArgs.probeDuration(of: url) ?? 0
        guard duration > 0 else { throw ConversionError.toolFailed("Couldn't read the length of this audio file.") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = ExternalTool.ffmpegArguments(["-v", "error", "-i", url.path, "-vn", "-ac", "1", "-ar", String(rate), "-f", "f32le", "-"])
        process.standardInput = FileHandle.nullDevice
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        try process.run()
        return try await withTaskCancellationHandler {
            var accumulator = PeakAccumulator(bucketCount: bucketCount, totalFrames: Int(duration * Double(rate)))
            var leftover = Data()
            var lastReport = Date()
            while true {
                try Task.checkCancellation()
                guard let chunk = try out.fileHandleForReading.read(upToCount: 64 * 1024), !chunk.isEmpty else { break }
                leftover.append(chunk)
                let usable = leftover.count - leftover.count % 4
                let samples = leftover.prefix(usable).withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                leftover.removeFirst(usable)
                accumulator.add(samples)
                if Date().timeIntervalSince(lastReport) > 0.1 { partial(accumulator.peaks); lastReport = Date() }
            }
            process.waitUntilExit()
            return accumulator.peaks
        } onCancel: {
            process.terminate()
        }
    }
}

/// Everything the audio editor changes, and the ffmpeg command that applies it.
public struct AudioTrimPlan: Equatable {
    public var start: Double
    public var end: Double
    public var fadeIn = 0.0
    public var fadeOut = 0.0
    public var volume = 1.0          // linear gain

    public init(start: Double, end: Double, fadeIn: Double = 0, fadeOut: Double = 0, volume: Double = 1) {
        self.start = start; self.end = end; self.fadeIn = fadeIn; self.fadeOut = fadeOut; self.volume = volume
    }

    public var length: Double { max(end - start, 0) }

    /// Fades are limited so they never overlap.
    public var effectiveFades: (in: Double, out: Double) {
        var fadeIn = max(self.fadeIn, 0), fadeOut = max(self.fadeOut, 0)
        if fadeIn + fadeOut > length, fadeIn + fadeOut > 0 {
            let scale = length / (fadeIn + fadeOut)
            fadeIn *= scale; fadeOut *= scale
        }
        return (fadeIn, fadeOut)
    }

    public func ffmpegArguments(input: URL, output: URL) -> [String] {
        var args = ["-y", "-ss", Self.number(start), "-i", input.path, "-t", Self.number(length), "-vn"]
        var filters: [String] = []
        let fades = effectiveFades
        if fades.in > 0.001 { filters.append("afade=t=in:st=0:d=\(Self.number(fades.in))") }
        if fades.out > 0.001 { filters.append("afade=t=out:st=\(Self.number(length - fades.out)):d=\(Self.number(fades.out))") }
        if abs(volume - 1) > 0.001 { filters.append("volume=\(Self.number(volume))") }
        if !filters.isEmpty { args += ["-af", filters.joined(separator: ",")] }
        switch output.pathExtension.lowercased() {
        case "mp3": args += ["-c:a", "libmp3lame", "-q:a", "2"]
        case "m4a", "aac": args += ["-c:a", "aac", "-b:a", "192k"]
        default: break
        }
        args += ["-loglevel", "error", output.path]
        return args
    }

    /// Two plans covering the file either side of `position` (settings stay on the outer ends).
    public func split(at position: Double) -> (AudioTrimPlan, AudioTrimPlan)? {
        guard position > start + TrimRange.minimumLength, position < end - TrimRange.minimumLength else { return nil }
        return (AudioTrimPlan(start: start, end: position, fadeIn: fadeIn, fadeOut: 0, volume: volume),
                AudioTrimPlan(start: position, end: end, fadeIn: 0, fadeOut: fadeOut, volume: volume))
    }

    static func number(_ value: Double) -> String { String(format: "%.3f", value) }
}

public enum AudioExport {
    public static func export(source: URL, plan: AudioTrimPlan, output: URL,
                              progress: @escaping @Sendable (Double) -> Void) async throws -> ConversionResult {
        guard let ffmpeg = ExternalTool.ffmpeg.path else {
            throw ConversionError.missingTool(name: ExternalTool.ffmpeg.name, installHint: ExternalTool.ffmpeg.installHint)
        }
        guard plan.length > 0 else { throw ConversionError.toolFailed("The selection is empty.") }
        try await FFmpegRunner.run(ffmpegPath: ffmpeg, arguments: plan.ffmpegArguments(input: source, output: output),
                                   totalDuration: plan.length, output: output, progress: progress)
        return ConversionResult(outputURL: output)
    }
}
