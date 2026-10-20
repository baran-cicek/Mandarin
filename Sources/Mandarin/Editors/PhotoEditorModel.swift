import AppKit
import Foundation

@MainActor
public final class PhotoEditorModel: ObservableObject {
    public let source: URL
    /// Pixel size of the image as displayed (EXIF orientation applied), before any edit.
    public let originalSize: CGSize
    private let proxy: CGImage
    private var previewTask: Task<Void, Never>?

    @Published var edits = PhotoEdits() { didSet { if edits != oldValue { schedulePreview() } } }
    @Published private(set) var preview: NSImage
    @Published var showOriginal = false
    @Published var aspect: AspectPreset = .free
    @Published public private(set) var cropRect: CGRect
    @Published var resizeEnabled = false
    @Published var linkRatio = true
    @Published public private(set) var targetWidth: Int
    @Published public private(set) var targetHeight: Int

    private var dragHandle: CropHandle?
    private var dragStartRect: CGRect = .zero
    private var dragActive = false

    private init(source: URL, originalSize: CGSize, proxy: CGImage) {
        self.source = source
        self.originalSize = originalSize
        self.proxy = proxy
        self.preview = NSImage(cgImage: proxy, size: NSSize(width: proxy.width, height: proxy.height))
        self.cropRect = CGRect(origin: .zero, size: originalSize)
        self.targetWidth = Int(originalSize.width)
        self.targetHeight = Int(originalSize.height)
    }

    /// Decodes off the main thread; the window only opens once this succeeds.
    public static func load(_ url: URL) async throws -> PhotoEditorModel {
        let (size, proxy) = try await Task.detached(priority: .userInitiated) { () -> (CGSize, CGImage) in
            guard let size = PhotoPipeline.pixelSize(of: url) else { throw ConversionError.cannotReadInput }
            return (size, try PhotoPipeline.decode(url, maxPixel: 1800))
        }.value
        return PhotoEditorModel(source: url, originalSize: size, proxy: proxy)
    }

    public var orientedSize: CGSize { edits.orientedSize(of: originalSize) }
    var cropRatio: CGFloat? { aspect.ratio(originalSize: orientedSize) }
    var cropIsFull: Bool { cropRect == CGRect(origin: .zero, size: orientedSize) }

    // MARK: Preview

    private func schedulePreview() {
        previewTask?.cancel()
        let proxy = self.proxy
        let edits = self.edits
        previewTask = Task { [weak self] in
            let image = try? await Task.detached(priority: .userInitiated) {
                try PhotoPipeline.preview(of: proxy, edits: edits)
            }.value
            guard !Task.isCancelled, let image, let self else { return }
            self.preview = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }
    }

    var originalImage: NSImage { NSImage(cgImage: proxy, size: NSSize(width: proxy.width, height: proxy.height)) }

    // MARK: Orientation

    public func rotate(clockwise: Bool) {
        edits.quarterTurns = (edits.quarterTurns + (clockwise ? 1 : 3)) % 4
        resetCrop()
    }

    public func flip(horizontal: Bool) {
        if horizontal { edits.flipHorizontal.toggle() } else { edits.flipVertical.toggle() }
    }

    // MARK: Crop

    public func resetCrop() {
        cropRect = CropGeometry.initialRect(in: orientedSize, ratio: cropRatio)
        syncResizeToCrop()
    }

    public func setAspect(_ preset: AspectPreset) {
        aspect = preset
        cropRect = CropGeometry.applying(ratio: cropRatio, to: cropRect, in: orientedSize)
        syncResizeToCrop()
    }

    public func setCrop(x: Int? = nil, y: Int? = nil, width: Int? = nil, height: Int? = nil) {
        var r = cropRect
        if let width { r.size.width = CGFloat(width) }
        if let height { r.size.height = CGFloat(height) }
        if let x { r.origin.x = CGFloat(x) }
        if let y { r.origin.y = CGFloat(y) }
        r.size.width = max(1, r.width); r.size.height = max(1, r.height)
        if let ratio = cropRatio, width != nil || height != nil {
            if width != nil { r.size.height = r.width / ratio } else { r.size.width = r.height * ratio }
        }
        cropRect = CropGeometry.pixelAligned(CropGeometry.clamped(r, in: orientedSize), in: orientedSize)
        syncResizeToCrop()
    }

    public func nudgeCrop(dx: CGFloat, dy: CGFloat) {
        cropRect = CropGeometry.moved(cropRect, by: CGSize(width: dx, height: dy), in: orientedSize)
        syncResizeToCrop()
    }

    public func dragChanged(start: CGPoint, current: CGPoint, display: CGRect) {
        guard display.width > 0 else { return }
        let scale = orientedSize.width / display.width
        if !dragActive {
            dragActive = true
            let viewRect = CGRect(x: display.minX + cropRect.minX / scale, y: display.minY + cropRect.minY / scale,
                                  width: cropRect.width / scale, height: cropRect.height / scale)
            dragHandle = CropGeometry.handle(at: start, in: viewRect)
            dragStartRect = cropRect
        }
        guard let handle = dragHandle else { return }
        let delta = CGSize(width: (current.x - start.x) * scale, height: (current.y - start.y) * scale)
        cropRect = CropGeometry.dragged(dragStartRect, handle: handle, delta: delta, ratio: cropRatio,
                                        in: orientedSize, minSize: max(8, orientedSize.width / 100))
        syncResizeToCrop()
    }

    public func dragEnded() {
        dragActive = false
        dragHandle = nil
        cropRect = CropGeometry.pixelAligned(cropRect, in: orientedSize)
        syncResizeToCrop()
    }

    // MARK: Resize

    private var croppedSize: CGSize { cropRect.size }

    private func syncResizeToCrop() {
        let size = croppedSize
        if !resizeEnabled || (linkRatio && size.height > 0) {
            if !resizeEnabled {
                targetWidth = Int(size.width.rounded()); targetHeight = Int(size.height.rounded())
            } else {
                targetHeight = ResizeMath.height(forWidth: targetWidth, ratio: size.width / size.height)
            }
        }
    }

    public func setResizeEnabled(_ enabled: Bool) {
        resizeEnabled = enabled
        if !enabled { syncResizeToCrop() }
    }

    public func setTargetWidth(_ value: Int) {
        targetWidth = min(max(value, 1), 20000)
        if linkRatio, cropRect.height > 0 { targetHeight = ResizeMath.height(forWidth: targetWidth, ratio: cropRect.width / cropRect.height) }
    }

    public func setTargetHeight(_ value: Int) {
        targetHeight = min(max(value, 1), 20000)
        if linkRatio, cropRect.height > 0 { targetWidth = ResizeMath.width(forHeight: targetHeight, ratio: cropRect.width / cropRect.height) }
    }

    // MARK: Reset / export

    public func resetAll() {
        edits = PhotoEdits()
        aspect = .free
        resizeEnabled = false
        resetCrop()
    }

    /// The edits to apply on export, folding in the crop and resize state.
    public var exportEdits: PhotoEdits {
        var result = edits
        result.crop = cropIsFull ? nil : cropRect
        result.outputSize = resizeEnabled ? CGSize(width: targetWidth, height: targetHeight) : nil
        return result
    }

    public var hasChanges: Bool { !exportEdits.isIdentity }
}
