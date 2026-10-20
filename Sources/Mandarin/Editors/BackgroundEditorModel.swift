import AppKit
import Foundation

@MainActor
public final class BackgroundEditorModel: ObservableObject {
    public enum RemovalMode: String, CaseIterable, Identifiable { case none = "Keep", solid = "Remove solid color", subject = "Remove background (subject)"
        public var id: String { rawValue } }
    public enum FillMode: String, CaseIterable, Identifiable { case none = "Transparent", solid = "Color", gradient = "Gradient"
        public var id: String { rawValue } }

    public let source: URL
    public let pixelSize: CGSize
    private let proxy: CGImage
    private var previewTask: Task<Void, Never>?

    @Published public var removalMode: RemovalMode = .none { didSet { schedulePreview() } }
    @Published public var keyColor: RGB { didSet { schedulePreview() } }
    @Published public var tolerance = 0.12 { didSet { schedulePreview() } }
    @Published public var contiguous = true { didSet { schedulePreview() } }
    @Published public var fillMode: FillMode = .solid { didSet { schedulePreview() } }
    @Published public var fillColor = RGB.white { didSet { schedulePreview() } }
    @Published public var gradientEnd = RGB(r: 0.55, g: 0.7, b: 1) { didSet { schedulePreview() } }
    @Published public var gradientAngle = 90.0 { didSet { schedulePreview() } }
    @Published public private(set) var preview: NSImage
    @Published public private(set) var working = false
    @Published public private(set) var notice: String?

    private init(source: URL, size: CGSize, proxy: CGImage, key: RGB) {
        self.source = source; self.pixelSize = size; self.proxy = proxy; self.keyColor = key
        self.preview = NSImage(cgImage: proxy, size: NSSize(width: proxy.width, height: proxy.height))
    }

    public static func load(_ url: URL) async throws -> BackgroundEditorModel {
        let (size, proxy, key) = try await Task.detached(priority: .userInitiated) { () -> (CGSize, CGImage, RGB) in
            guard let size = PhotoPipeline.pixelSize(of: url) else { throw ConversionError.cannotReadInput }
            let proxy = try PhotoPipeline.decode(url, maxPixel: 1200)
            return (size, proxy, try BackgroundTool.guessBackgroundColor(proxy))
        }.value
        return BackgroundEditorModel(source: url, size: size, proxy: proxy, key: key)
    }

    public var edit: BackgroundEdit {
        let removal: BackgroundRemoval
        switch removalMode {
        case .none: removal = .none
        case .solid: removal = .solidColor(key: keyColor, tolerance: tolerance, contiguous: contiguous)
        case .subject: removal = .subject
        }
        let fill: BackgroundFill
        switch fillMode {
        case .none: fill = .none
        case .solid: fill = .solid(fillColor)
        case .gradient: fill = .gradient(from: fillColor, to: gradientEnd, angleDegrees: gradientAngle)
        }
        return BackgroundEdit(removal: removal, fill: fill)
    }

    public var hasChanges: Bool { edit.removal != .none || edit.fill != .none }
    public var subjectAvailable: Bool { BackgroundTool.subjectMaskAvailable }

    /// Sets the key colour from a point given in image fractions (0...1, top-left origin).
    public func pickKey(atFraction p: CGPoint) {
        let point = CGPoint(x: p.x * CGFloat(proxy.width), y: p.y * CGFloat(proxy.height))
        if let color = BackgroundTool.color(at: point, in: proxy) { keyColor = color }
    }

    private func schedulePreview() {
        previewTask?.cancel()
        let proxy = self.proxy, edit = self.edit
        working = true
        previewTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            let outcome: Result<CGImage, Error> = await Task.detached(priority: .userInitiated) {
                Result { try BackgroundTool.apply(edit, to: proxy) }
            }.value
            guard !Task.isCancelled, let self else { return }
            self.working = false
            switch outcome {
            case .success(let image):
                self.notice = nil
                self.preview = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            case .failure(let error):
                self.notice = error is CancellationError ? nil : error.localizedDescription
            }
        }
    }
}
