import AVFoundation
import Foundation

/// AVPlayer wrapper shared by the audio and video editors: plays a selected
/// range, reports the playhead, and says plainly when a format can't be previewed.
@MainActor
public final class MediaPreviewPlayer: ObservableObject {
    public let player = AVPlayer()
    @Published public private(set) var playhead = 0.0
    @Published public private(set) var isPlaying = false
    @Published public private(set) var error: String?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var rangeEnd: Double?

    public init(url: URL) {
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        let box = WeakBox(self)
        statusObservation = item.observe(\.status, options: [.new]) { item, _ in
            Task { @MainActor in
                if item.status == .failed { box.value?.error = "This format can't be previewed here. You can still trim it by typing times." }
            }
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1.0 / 30, preferredTimescale: 600), queue: .main) { time in
            Task { @MainActor in box.value?.tick(time.seconds) }
        }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
    }

    private func tick(_ seconds: Double) {
        guard seconds.isFinite else { return }
        playhead = seconds
        if let rangeEnd, seconds >= rangeEnd - 0.01 {
            player.pause()
            isPlaying = false
            self.rangeEnd = nil
        }
        if player.rate == 0 && isPlaying && rangeEnd == nil { isPlaying = false }
    }

    public func seek(to seconds: Double) {
        playhead = seconds
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Plays from `start` (or the playhead, if it is inside the range) to `end`.
    public func playRange(start: Double, end: Double, volume: Double = 1) {
        guard error == nil else { return }
        if playhead < start || playhead >= end - 0.05 { seek(to: start) }
        rangeEnd = end
        player.volume = Float(min(max(volume, 0), 1))
        player.play()
        isPlaying = true
    }

    public func pause() {
        player.pause()
        isPlaying = false
        rangeEnd = nil
    }

    public func toggle(start: Double, end: Double, volume: Double = 1) {
        if isPlaying { pause() } else { playRange(start: start, end: end, volume: volume) }
    }
}
