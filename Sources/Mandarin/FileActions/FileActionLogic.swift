import Foundation

/// The pure, non-UI logic behind Copy/Move/Copy Path/Open in Terminal,
/// pulled out of `FileActionRunner` so it can be exercised by
/// `MandarinSelfTests` without a folder picker, a real drag, or any other
/// UI — same functions the app actually calls, not a parallel copy.
public enum FileActionLogic {
    /// Copies or moves `url` into `folder` under a non-clobbering name,
    /// returning the final destination. Throws whatever `FileManager` throws
    /// — a missing or read-only destination surfaces as a normal error, not
    /// a crash.
    public static func copyOrMoveItem(at url: URL, into folder: URL, move: Bool) throws -> URL {
        let destination = OutputPathPlanner.nonClobberingURL(copying: url, into: folder)
        if move {
            try FileManager.default.moveItem(at: url, to: destination)
        } else {
            try FileManager.default.copyItem(at: url, to: destination)
        }
        return destination
    }

    /// Clipboard text for Copy Path: one full path per line.
    public static func pathsText(for urls: [URL]) -> String {
        urls.map(\.path).joined(separator: "\n")
    }

    /// The folder Open in Terminal should open: the item itself if it's a
    /// folder, otherwise its containing folder.
    public static func folderURL(for url: URL) -> URL {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true ? url : url.deletingLastPathComponent()
    }
}
