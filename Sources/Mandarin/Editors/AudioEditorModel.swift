import AVFoundation
import Foundation

@MainActor
public final class AudioEditorModel: ObservableObject {
    public let source: URL
    public let duration: Double
    public let player: MediaPreviewPlayer
    public let drag = TimelineDragState()
    public static let bucketCount = 1200

    @Published public private(set) var trim: TrimRange
    @Published public private(set) var peaks: [Float] = []
    @Published public private(set) var waveformLoading = true
    @Published public private(set) var waveformError: String?
    @Published public var fadeIn = 0.0
    @Published public var fadeOut = 0.0
    @Published public var volume = 1.0
    private var waveformTask: Task<Void, Never>?

    private init(source: URL, duration: Double) {
        self.source = source
        self.duration = duration
        self.trim = TrimRange(duration: duration)
        self.player = MediaPreviewPlayer(url: source)
    }

    public static func load(_ url: URL) async throws -> AudioEditorModel {
        let duration = try await Task.detached(priority: .userInitiated) { () -> Double in
            if let asset = try? await AVURLAsset(url: url).load(.duration), asset.seconds.isFinite, asset.seconds > 0 { return asset.seconds }
            if let probed = FileToolMediaArgs.probeDuration(of: url), probed > 0 { return probed }
            throw ConversionError.toolFailed("Couldn't read this audio file.")
        }.value
        let model = AudioEditorModel(source: url, duration: duration)
        model.startWaveform()
        return model
    }

    deinit { waveformTask?.cancel() }

    public func cancelWork() { waveformTask?.cancel(); player.pause() }

    private func startWaveform() {
        let url = source
        let box = WeakBox(self)
        let report: @Sendable ([Float]) -> Void = { partial in
            Task { @MainActor in box.value?.peaks = partial }
        }
        waveformTask = Task { [weak self] in
            do {
                let final = try await Task.detached(priority: .utility) {
                    try await WaveformLoader.load(url, bucketCount: AudioEditorModel.bucketCount, partial: report)
                }.value
                self?.peaks = final
            } catch is CancellationError {
            } catch {
                self?.waveformError = error.localizedDescription
            }
            self?.waveformLoading = false
        }
    }

    public func setStart(_ value: Double) { trim.setStart(value); clampFades() }
    public func setEnd(_ value: Double) { trim.setEnd(value); clampFades() }

    private func clampFades() {
        fadeIn = min(fadeIn, trim.length)
        fadeOut = min(fadeOut, trim.length)
    }

    public var plan: AudioTrimPlan {
        AudioTrimPlan(start: trim.start, end: trim.end, fadeIn: fadeIn, fadeOut: fadeOut, volume: volume)
    }

    public var hasChanges: Bool { !trim.isFull || fadeIn > 0 || fadeOut > 0 || abs(volume - 1) > 0.001 }
    public var canSplit: Bool { plan.split(at: player.playhead) != nil }
    public var previewVolume: Double { min(volume, 1) }

    public func togglePlayback() { player.toggle(start: trim.start, end: trim.end, volume: previewVolume) }
}
