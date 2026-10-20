import Foundation
import UniformTypeIdentifiers

public enum OutputPathPlanner {
    /// `file.png`, then `file 2.png`, `file 3.png`, ... if those already exist.
    public static func nonClobberingURL(for sourceURL: URL, outputType: UTType, in folder: URL) -> URL {
        let extensionString = FormatCatalog.fileExtension(for: outputType)
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        return firstAvailable(baseName: baseName, extension: extensionString, in: folder)
    }

    /// Same non-clobbering naming, but keeping the source's own name and
    /// extension — for Copy/Move, which don't change the file's format.
    /// Works for extensionless files and folders too.
    public static func nonClobberingURL(copying sourceURL: URL, into folder: URL) -> URL {
        let extensionString = sourceURL.pathExtension
        let baseName = extensionString.isEmpty ? sourceURL.lastPathComponent : sourceURL.deletingPathExtension().lastPathComponent
        return firstAvailable(baseName: baseName, extension: extensionString, in: folder)
    }

    /// A non-clobbering folder name (`report`, then `report 2`, ...) for
    /// multi-page outputs (PDF/slide page images) — these go in their own
    /// new folder, never as loose numbered files next to other output.
    public static func nonClobberingFolder(named baseName: String, in folder: URL) -> URL {
        var candidate = folder.appendingPathComponent(baseName)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(baseName) \(counter)")
            counter += 1
        }
        return candidate
    }

    private static func firstAvailable(baseName: String, extension extensionString: String, in folder: URL) -> URL {
        func url(for name: String) -> URL {
            extensionString.isEmpty ? folder.appendingPathComponent(name) : folder.appendingPathComponent(name).appendingPathExtension(extensionString)
        }

        var candidate = url(for: baseName)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = url(for: "\(baseName) \(counter)")
            counter += 1
        }
        return candidate
    }
}
