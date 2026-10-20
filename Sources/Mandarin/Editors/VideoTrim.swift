import AVFoundation
import AppKit
import Foundation

public struct VideoInfo: Equatable {
    public let duration: Double
    public let size: CGSize        // as displayed (rotation applied)

    /// AVFoundation first; ffprobe for containers it can't open (MKV, WebM, ...).
    public static func probe(_ url: URL) async throws -> VideoInfo {
        let asset = AVURLAsset(url: url)
        if let duration = try? await asset.load(.duration).seconds, duration.isFinite, duration > 0,
           let track = try? await asset.loadTracks(withMediaType: .video).first,
           let (natural, transform) = try? await track.load(.naturalSize, .preferredTransform) {
            let size = natural.applying(transform)
            if abs(size.width) > 0 && abs(size.height) > 0 {
                return VideoInfo(duration: duration, size: CGSize(width: abs(size.width), height: abs(size.height)))
            }
        }
        guard let ffprobe = ExternalTool.ffprobe.path else {
            throw ConversionError.missingTool(name: ExternalTool.ffprobe.name, installHint: ExternalTool.ffprobe.installHint)
        }
        let data = try await ProcessRunner.run(ffprobe, arguments: [
            "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height:stream_side_data=rotation:format=duration",
            "-of", "json", url.path,
        ])
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stream = (json["streams"] as? [[String: Any]])?.first,
              let width = stream["width"] as? Double ?? (stream["width"] as? Int).map(Double.init),
              let height = stream["height"] as? Double ?? (stream["height"] as? Int).map(Double.init),
              let durationText = (json["format"] as? [String: Any])?["duration"] as? String, let duration = Double(durationText) else {
            throw ConversionError.toolFailed("Couldn't read this video.")
        }
        var size = CGSize(width: width, height: height)
        if let rotation = ((stream["side_data_list"] as? [[String: Any]])?.compactMap { $0["rotation"] as? Double }.first),
           Int(abs(rotation)) % 180 == 90 {
            size = CGSize(width: height, height: width)
        }
        return VideoInfo(duration: duration, size: size)
    }
}

public struct VideoTrimPlan: Equatable {
    public var start: Double
    public var end: Double
    public var crop: CGRect?            // pixels of the displayed video, top-left origin
    public var fastCut: Bool            // stream copy: lossless, cuts snap to keyframes. Ignored with a crop.

    public init(start: Double, end: Double, crop: CGRect? = nil, fastCut: Bool = true) {
        self.start = start; self.end = end; self.crop = crop; self.fastCut = fastCut
    }

    public var length: Double { max(end - start, 0) }
    /// True when the file can be cut without re-encoding.
    public var isLossless: Bool { crop == nil && fastCut }

    /// Crop box with even coordinates, as H.264/yuv420 requires.
    public static func evenCrop(_ crop: CGRect) -> (w: Int, h: Int, x: Int, y: Int) {
        let w = max(2, Int(crop.width) / 2 * 2), h = max(2, Int(crop.height) / 2 * 2)
        return (w, h, Int(crop.minX) / 2 * 2, Int(crop.minY) / 2 * 2)
    }

    public func ffmpegArguments(input: URL, output: URL) -> [String] {
        var args = ["-y", "-ss", String(format: "%.3f", start), "-i", input.path, "-t", String(format: "%.3f", length)]
        if isLossless {
            args += ["-map", "0:v:0", "-map", "0:a?", "-c", "copy", "-avoid_negative_ts", "make_zero"]
        } else {
            if let crop {
                let c = Self.evenCrop(crop)
                args += ["-vf", "crop=\(c.w):\(c.h):\(c.x):\(c.y)"]
            }
            switch output.pathExtension.lowercased() {
            case "mp4", "m4v", "mov", "mkv": args += ["-c:v", "libx264", "-crf", "18", "-preset", "medium", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k"]
            case "webm": args += ["-c:v", "libvpx-vp9", "-crf", "30", "-b:v", "0", "-c:a", "libopus"]
            default: break
            }
        }
        args += ["-loglevel", "error", output.path]
        return args
    }
}

public enum VideoExport {
    public static func export(source: URL, plan: VideoTrimPlan, output: URL,
                              progress: @escaping @Sendable (Double) -> Void) async throws -> ConversionResult {
        guard let ffmpeg = ExternalTool.ffmpeg.path else {
            throw ConversionError.missingTool(name: ExternalTool.ffmpeg.name, installHint: ExternalTool.ffmpeg.installHint)
        }
        guard plan.length > 0 else { throw ConversionError.toolFailed("The selection is empty.") }
        try await FFmpegRunner.run(ffmpegPath: ffmpeg, arguments: plan.ffmpegArguments(input: source, output: output),
                                   totalDuration: plan.length, output: output, progress: progress)
        return ConversionResult(outputURL: output, warning: plan.isLossless ? "Cut without re-encoding; the start may snap to the nearest earlier keyframe" : nil)
    }
}

public enum ThumbnailStrip {
    /// `count` frames spread over the video; nil entries are frames that couldn't be read.
    /// Delivered one by one through `deliver` so the strip fills in as it goes.
    public static func generate(url: URL, duration: Double, count: Int, deliver: @escaping @Sendable (Int, NSImage) -> Void) async {
        let times = (0..<count).map { duration * (Double($0) + 0.5) / Double(count) }
        let asset = AVURLAsset(url: url)
        if (try? await asset.loadTracks(withMediaType: .video).first) != nil {
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 240, height: 240)
            generator.requestedTimeToleranceBefore = .positiveInfinity
            generator.requestedTimeToleranceAfter = .positiveInfinity
            var index = 0
            for await result in generator.images(for: times.map { CMTime(seconds: $0, preferredTimescale: 600) }) {
                if Task.isCancelled { return }
                if case .success(_, let image, _) = result {
                    deliver(index, NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)))
                }
                index += 1
            }
            return
        }
        guard let ffmpeg = ExternalTool.ffmpeg.path else { return }
        for (index, time) in times.enumerated() {
            if Task.isCancelled { return }
            if let data = try? await ProcessRunner.run(ffmpeg, arguments: ["-v", "error", "-ss", String(format: "%.3f", time), "-i", url.path,
                                                                           "-frames:v", "1", "-vf", "scale=240:-2", "-f", "image2pipe", "-c:v", "png", "-"]),
               let image = NSImage(data: data) {
                deliver(index, image)
            }
        }
    }
}
