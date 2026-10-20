import AVFoundation
import AppKit
import Foundation

@MainActor
public final class VideoEditorModel: ObservableObject {
    public let source: URL
    public let info: VideoInfo
    public let player: MediaPreviewPlayer
    public let drag = TimelineDragState()
    public static let thumbnailCount = 12

    @Published public private(set) var trim: TrimRange
    @Published public private(set) var thumbnails: [Int: NSImage] = [:]
    @Published public var cropEnabled = false { didSet { if cropEnabled { fastCut = false } } }
    @Published public var aspect: AspectPreset = .free
    @Published public private(set) var cropRect: CGRect
    @Published public var fastCut = true
    private var thumbnailTask: Task<Void, Never>?
    private var dragHandle: CropHandle?
    private var dragStart: CGRect = .zero
    private var dragActive = false

    private init(source: URL, info: VideoInfo) {
        self.source = source; self.info = info
        self.trim = TrimRange(duration: info.duration)
        self.cropRect = CGRect(origin: .zero, size: info.size)
        self.player = MediaPreviewPlayer(url: source)
    }

    public static func load(_ url: URL) async throws -> VideoEditorModel {
        let info = try await VideoInfo.probe(url)
        let model = VideoEditorModel(source: url, info: info)
        model.startThumbnails()
        return model
    }

    deinit { thumbnailTask?.cancel() }

    public func cancelWork() { thumbnailTask?.cancel(); player.pause() }

    private func startThumbnails() {
        let url = source, duration = info.duration
        let box = WeakBox(self)
        let deliver: @Sendable (Int, NSImage) -> Void = { index, image in
            Task { @MainActor in box.value?.thumbnails[index] = image }
        }
        thumbnailTask = Task.detached(priority: .utility) {
            await ThumbnailStrip.generate(url: url, duration: duration, count: VideoEditorModel.thumbnailCount, deliver: deliver)
        }
    }

    public func setStart(_ value: Double) { trim.setStart(value) }
    public func setEnd(_ value: Double) { trim.setEnd(value) }

    public var cropRatio: CGFloat? { aspect.ratio(originalSize: info.size) }

    public var plan: VideoTrimPlan {
        let crop = cropEnabled && cropRect != CGRect(origin: .zero, size: info.size) ? CropGeometry.pixelAligned(cropRect, in: info.size) : nil
        return VideoTrimPlan(start: trim.start, end: trim.end, crop: crop, fastCut: fastCut)
    }

    public var hasChanges: Bool { !trim.isFull || plan.crop != nil }

    public func setAspect(_ preset: AspectPreset) {
        aspect = preset
        cropRect = CropGeometry.applying(ratio: cropRatio, to: cropRect, in: info.size)
    }

    public func resetCrop() { cropRect = CropGeometry.initialRect(in: info.size, ratio: cropRatio) }

    public func setCrop(x: Int? = nil, y: Int? = nil, width: Int? = nil, height: Int? = nil) {
        var r = cropRect
        if let width { r.size.width = CGFloat(width) }
        if let height { r.size.height = CGFloat(height) }
        if let x { r.origin.x = CGFloat(x) }
        if let y { r.origin.y = CGFloat(y) }
        r.size.width = max(2, r.width); r.size.height = max(2, r.height)
        if let ratio = cropRatio, width != nil || height != nil {
            if width != nil { r.size.height = r.width / ratio } else { r.size.width = r.height * ratio }
        }
        cropRect = CropGeometry.pixelAligned(CropGeometry.clamped(r, in: info.size), in: info.size)
    }

    public func nudgeCrop(dx: CGFloat, dy: CGFloat) {
        cropRect = CropGeometry.moved(cropRect, by: CGSize(width: dx, height: dy), in: info.size)
    }

    public func dragChanged(start: CGPoint, current: CGPoint, display: CGRect) {
        guard display.width > 0 else { return }
        let scale = info.size.width / display.width
        if !dragActive {
            dragActive = true
            let viewRect = CGRect(x: display.minX + cropRect.minX / scale, y: display.minY + cropRect.minY / scale,
                                  width: cropRect.width / scale, height: cropRect.height / scale)
            dragHandle = CropGeometry.handle(at: start, in: viewRect)
            dragStart = cropRect
        }
        guard let handle = dragHandle else { return }
        let delta = CGSize(width: (current.x - start.x) * scale, height: (current.y - start.y) * scale)
        cropRect = CropGeometry.dragged(dragStart, handle: handle, delta: delta, ratio: cropRatio, in: info.size, minSize: max(16, info.size.width / 50))
    }

    public func dragEnded() {
        dragActive = false; dragHandle = nil
        cropRect = CropGeometry.pixelAligned(cropRect, in: info.size)
    }

    public func togglePlayback() { player.toggle(start: trim.start, end: trim.end) }
}
