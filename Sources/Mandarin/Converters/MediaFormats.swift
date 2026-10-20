import UniformTypeIdentifiers

/// The audio/video formats Mandarin knows about. Same role as
/// `ImageFormats`: one table the registry, the wheel, and the converters
/// all read instead of each hard-coding the list.
enum MediaFormats {
    enum Domain { case audio, video }
    enum Engine { case avfoundation, ffmpeg }

    struct Format {
        let type: UTType
        let fileExtension: String
        let icon: String
        let domain: Domain
        let engine: Engine
    }

    /// "opus" and "ogg" share one system UTI (`org.xiph.ogg-audio`) — Opus
    /// is technically an Ogg container variant — so Opus needs its own type
    /// here to stay distinguishable as a separate Convert target.
    static let opus = UTType(exportedAs: "\(AppIdentity.bundleID).format.opus", conformingTo: .audio)
    static let flac = UTType.known("org.xiph.flac", ext: "flac")
    static let ogg = UTType.known("org.xiph.ogg-audio", ext: "ogg")
    static let wma = UTType.known("com.microsoft.windows-media-wma", ext: "wma")
    static let mkv = UTType.known("org.matroska.mkv", ext: "mkv")
    static let webm = UTType.known("org.webmproject.webm", ext: "webm")
    static let wmv = UTType.known("com.microsoft.windows-media-wmv", ext: "wmv")

    static let all: [Format] = [
        // Audio
        Format(type: .mp3, fileExtension: "mp3", icon: "waveform", domain: .audio, engine: .ffmpeg),
        Format(type: .mpeg4Audio, fileExtension: "m4a", icon: "waveform", domain: .audio, engine: .avfoundation),
        Format(type: .wav, fileExtension: "wav", icon: "waveform", domain: .audio, engine: .ffmpeg),
        Format(type: flac, fileExtension: "flac", icon: "waveform", domain: .audio, engine: .ffmpeg),
        Format(type: ogg, fileExtension: "ogg", icon: "waveform", domain: .audio, engine: .ffmpeg),
        Format(type: opus, fileExtension: "opus", icon: "waveform", domain: .audio, engine: .ffmpeg),
        Format(type: .aiff, fileExtension: "aiff", icon: "waveform", domain: .audio, engine: .ffmpeg),
        Format(type: wma, fileExtension: "wma", icon: "waveform", domain: .audio, engine: .ffmpeg),
        // Video (GIF included — functionally a video-conversion target even
        // though its UTI is nominally an image type)
        Format(type: .mpeg4Movie, fileExtension: "mp4", icon: "video", domain: .video, engine: .avfoundation),
        Format(type: .quickTimeMovie, fileExtension: "mov", icon: "video", domain: .video, engine: .avfoundation),
        Format(type: mkv, fileExtension: "mkv", icon: "video", domain: .video, engine: .ffmpeg),
        Format(type: webm, fileExtension: "webm", icon: "video", domain: .video, engine: .ffmpeg),
        Format(type: .avi, fileExtension: "avi", icon: "video", domain: .video, engine: .ffmpeg),
        Format(type: wmv, fileExtension: "wmv", icon: "video", domain: .video, engine: .ffmpeg),
        Format(type: .gif, fileExtension: "gif", icon: "photo.on.rectangle.angled", domain: .video, engine: .ffmpeg),
    ]

    static func format(for type: UTType) -> Format? {
        all.first { $0.type == type }
    }
}
