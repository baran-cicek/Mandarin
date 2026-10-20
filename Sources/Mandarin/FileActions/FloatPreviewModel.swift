import AppKit
import QuickLookThumbnailing

final class FloatPreviewModel: ObservableObject {
    let url: URL
    @Published var image: NSImage

    init(url: URL) {
        self.url = url
        self.image = NSWorkspace.shared.icon(forFile: url.path)
        loadThumbnail()
    }

    private func loadThumbnail() {
        let size = CGSize(width: 240, height: 240)
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            guard let representation else { return }
            DispatchQueue.main.async {
                self?.image = representation.nsImage
            }
        }
    }
}
