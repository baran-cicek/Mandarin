import UniformTypeIdentifiers

/// The image-family formats Mandarin knows about, in Convert-wheel display
/// order. Centralized so the registry, the wheel, and the encoder all agree
/// on type/extension/icon without duplicating the list.
enum ImageFormats {
    struct Format {
        let type: UTType
        let fileExtension: String
        let icon: String
    }

    static let webp = UTType.webP
    static let avif = UTType.known("public.avif", ext: "avif")

    /// Output formats, in wheel order. SVG is deliberately absent — input
    /// only, per spec.
    static let outputs: [Format] = [
        Format(type: .jpeg, fileExtension: "jpg", icon: "photo"),
        Format(type: .png, fileExtension: "png", icon: "photo"),
        Format(type: webp, fileExtension: "webp", icon: "photo"),
        Format(type: .heic, fileExtension: "heic", icon: "photo"),
        Format(type: .tiff, fileExtension: "tiff", icon: "photo"),
        Format(type: avif, fileExtension: "avif", icon: "photo"),
        Format(type: .bmp, fileExtension: "bmp", icon: "photo"),
        Format(type: .pdf, fileExtension: "pdf", icon: "doc.richtext"),
    ]

    static func format(for type: UTType) -> Format? {
        outputs.first { $0.type == type }
    }
}
