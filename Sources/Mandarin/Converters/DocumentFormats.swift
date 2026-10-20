import UniformTypeIdentifiers

/// The "Documents" format family. PAGES is deliberately absent: no tool
/// available here (native frameworks, pandoc, LibreOffice) can write
/// Apple's proprietary iWork format, and reading it reliably would mean
/// reaching into its bundle for a QuickLook preview PDF rather than real
/// content — a fake, not a conversion. Per spec: say so, don't fake it.
public enum DocumentFormats {
    enum Engine { case native, pandoc }

    struct Format {
        let type: UTType
        let fileExtension: String
        let icon: String
        let engine: Engine
    }

    public static let docx = UTType.known(nil, ext: "docx")
    static let markdown = UTType.known(nil, ext: "md")
    static let textClipping = UTType.known("com.apple.finder.textclipping", ext: "textClipping")

    /// Output formats, in Convert-wheel order. HTML is output-only per
    /// spec (not meaningfully round-tripped back from HTML here).
    static let outputs: [Format] = [
        Format(type: docx, fileExtension: "docx", icon: "doc.text", engine: .native),
        Format(type: markdown, fileExtension: "md", icon: "doc.plaintext", engine: .pandoc),
        Format(type: .plainText, fileExtension: "txt", icon: "doc.plaintext", engine: .native),
        Format(type: .epub, fileExtension: "epub", icon: "book", engine: .pandoc),
        Format(type: .html, fileExtension: "html", icon: "chevron.left.forwardslash.chevron.right", engine: .native),
    ]

    static func format(for type: UTType) -> Format? {
        outputs.first { $0.type == type }
    }
}
