import Foundation

/// ffmpeg filter-argument helpers for the video File Tools.
public enum FileToolMediaArgs {
    public static func probeDuration(of url: URL) -> Double? {
        guard let ffprobePath = ExternalTool.ffprobe.path else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobePath)
        process.arguments = ["-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", url.path]
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let string = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return Double(string)
    }

    /// Right-angle rotations use `transpose` (lossless, no interpolation);
    /// anything else falls back to the `rotate` filter.
    public static func rotationFilter(degrees: Double) -> [String] {
        let normalized = ((Int(degrees.rounded()) % 360) + 360) % 360
        switch normalized {
        case 90: return ["-vf", "transpose=1"]
        case 180: return ["-vf", "transpose=1,transpose=1"]
        case 270: return ["-vf", "transpose=2"]
        case 0: return []
        default:
            let radians = degrees * .pi / 180
            return ["-vf", "rotate=\(radians):fillcolor=black"]
        }
    }
}
