import Foundation

/// A command-line tool Mandarin shells out to for formats native frameworks
/// can't handle. Resolved once at startup by checking common Homebrew
/// install locations (the app is unsandboxed, so this is just a file check).
public struct ExternalTool {
    public let name: String
    public let installHint: String
    public let path: String?

    public var isAvailable: Bool { path != nil }

    private static let searchDirectories = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/opt/local/bin",
    ]

    private static func locate(_ binaryName: String) -> String? {
        for dir in searchDirectories {
            let candidate = dir + "/" + binaryName
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    public static let ffmpeg = ExternalTool(
        name: "ffmpeg",
        installHint: "Install it with: brew install ffmpeg",
        path: locate("ffmpeg")
    )

    public static let ffprobe = ExternalTool(
        name: "ffprobe",
        installHint: "Installed alongside ffmpeg: brew install ffmpeg",
        path: locate("ffprobe")
    )

    public static let cwebp = ExternalTool(
        name: "cwebp",
        installHint: "Install it with: brew install webp",
        path: locate("cwebp")
    )

    public static let pandoc = ExternalTool(
        name: "pandoc",
        installHint: "Install it with: brew install pandoc",
        path: locate("pandoc")
    )

    public static let soffice = ExternalTool(
        name: "soffice",
        installHint: "Install it with: brew install --cask libreoffice",
        path: locate("soffice")
    )

    public static let unar = ExternalTool(
        name: "unar",
        installHint: "Install it with: brew install unar",
        path: locate("unar")
    )

    /// ffmpeg reads the keyboard by default and stalls when started from a terminal;
    /// every launch gets `-nostdin` (and the callers also point stdin at /dev/null).
    public static func ffmpegArguments(_ arguments: [String]) -> [String] {
        arguments.first == "-nostdin" ? arguments : ["-nostdin"] + arguments
    }

    static func checkAllAtStartup() {
        for tool in [ffmpeg, ffprobe, cwebp, pandoc, soffice, unar] {
            NSLog("\(AppIdentity.name): tool '\(tool.name)' \(tool.isAvailable ? "found at \(tool.path!)" : "NOT FOUND — \(tool.installHint)")")
        }
    }
}
