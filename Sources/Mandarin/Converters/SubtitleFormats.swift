import UniformTypeIdentifiers

/// SRT and VTT as Convert targets; TXT export reuses the existing shared
/// `.plainText` entry (from `DocumentFormats`) rather than re-declaring it.
public enum SubtitleFormats {
    struct Format {
        let type: UTType
        let fileExtension: String
        let icon: String
    }

    public static let srt = UTType.known(nil, ext: "srt")
    public static let vtt = UTType.known(nil, ext: "vtt")

    static let outputs: [Format] = [
        Format(type: srt, fileExtension: "srt", icon: "captions.bubble"),
        Format(type: vtt, fileExtension: "vtt", icon: "captions.bubble"),
    ]

    static func format(for type: UTType) -> Format? {
        outputs.first { $0.type == type }
    }
}
