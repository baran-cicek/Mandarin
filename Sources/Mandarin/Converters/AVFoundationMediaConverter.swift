import AVFoundation
import UniformTypeIdentifiers

/// `AVAssetExportSession` isn't `Sendable`, but `exportAsynchronously`'s
/// completion handler is only ever invoked once the session is done, after
/// which we only read its (by-then-immutable) final `status`/`error` — this
/// box just tells the compiler we've verified that ourselves.
private final class UncheckedBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

/// Handles the formats AVFoundation is the genuinely reliable, native
/// choice for: M4A audio and MP4/MOV video, via `AVAssetExportSession`.
/// Everything else in the audio/video world goes through
/// `FFmpegMediaConverter` instead — see `MediaFormats.Format.engine`.
public final class AVFoundationMediaConverter: Converter {
    public init() {}

    public func canConvert(from: UTType, to: UTType) -> Bool {
        guard let toFormat = MediaFormats.format(for: to), toFormat.engine == .avfoundation else { return false }
        guard let fromFormat = MediaFormats.format(for: from) else { return false }
        return !(fromFormat.domain == .audio && toFormat.domain == .video)
    }

    public func convert(input: URL, output: URL, options: ConversionOptions, progress: @escaping (Double) -> Void) async throws -> ConversionResult {
        if FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.removeItem(at: output)
        }

        let asset = AVURLAsset(url: input)
        let outputFileType = Self.fileType(for: output)
        let presetName = outputFileType == .m4a ? AVAssetExportPresetAppleM4A : AVAssetExportPresetHighestQuality

        guard let session = AVAssetExportSession(asset: asset, presetName: presetName) else {
            throw ConversionError.cannotReadInput
        }
        session.outputURL = output
        session.outputFileType = outputFileType
        session.shouldOptimizeForNetworkUse = true

        let progressTask = Task {
            while !Task.isCancelled {
                progress(Double(session.progress))
                try? await Task.sleep(for: .milliseconds(200))
            }
        }

        let box = UncheckedBox(session)

        do {
            try await withTaskCancellationHandler(operation: {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    box.value.exportAsynchronously {
                        switch box.value.status {
                        case .completed:
                            continuation.resume()
                        case .cancelled:
                            continuation.resume(throwing: CancellationError())
                        case .failed:
                            continuation.resume(throwing: box.value.error ?? ConversionError.toolFailed("Export failed."))
                        default:
                            continuation.resume(throwing: ConversionError.toolFailed("Unexpected export status."))
                        }
                    }
                }
            }, onCancel: {
                session.cancelExport()
            })
        } catch {
            progressTask.cancel()
            try? FileManager.default.removeItem(at: output)
            throw error
        }

        progressTask.cancel()
        progress(1.0)
        return ConversionResult(outputURL: output)
    }

    private static func fileType(for url: URL) -> AVFileType {
        switch url.pathExtension.lowercased() {
        case "m4a": return .m4a
        case "mov": return .mov
        default: return .mp4
        }
    }
}
