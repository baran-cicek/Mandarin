import UniformTypeIdentifiers

/// ZIP/TAR/GZIP as output (for *any* file or folder — "compress this" is
/// a universal action, not gated by input type, same spirit as File
/// Actions); RAR as input only, which — paired with ZIP/TAR/GZIP being
/// outputs — means RAR→ZIP/TAR/GZIP (extract, then repack) is the one
/// archive→archive route offered. No tool here can create a RAR (that's
/// a proprietary, patent-encumbered format outside anything on this Mac),
/// so RAR is never an output.
enum ArchiveFormats {
    struct Format {
        let type: UTType
        let fileExtension: String
        let icon: String
    }

    static let tar = UTType.known(nil, ext: "tar")
    static let gzip = UTType.known(nil, ext: "gz")
    static let rar = UTType.known("com.rarlab.rar-archive", ext: "rar")

    static let outputs: [Format] = [
        Format(type: .zip, fileExtension: "zip", icon: "doc.zipper"),
        Format(type: tar, fileExtension: "tar", icon: "doc.zipper"),
        Format(type: gzip, fileExtension: "gz", icon: "doc.zipper"),
    ]

    static func format(for type: UTType) -> Format? {
        outputs.first { $0.type == type }
    }

    static func isArchiveOutputType(_ type: UTType) -> Bool {
        format(for: type) != nil
    }
}
