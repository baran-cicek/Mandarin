import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Output naming shared by every editor: a new copy next to the original
/// ("photo edited.png", then "photo edited 2.png"), never overwriting.
public enum EditorNaming {
    public static func outputURL(for source: URL, suffix: String = "edited", extension ext: String? = nil, in folder: URL) -> URL {
        let base = source.deletingPathExtension().lastPathComponent + " " + suffix
        let fileExtension = ext ?? source.pathExtension
        func url(_ name: String) -> URL {
            fileExtension.isEmpty ? folder.appendingPathComponent(name)
                : folder.appendingPathComponent(name).appendingPathExtension(fileExtension)
        }
        var candidate = url(base)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = url("\(base) \(counter)")
            counter += 1
        }
        return candidate
    }
}

/// Which visual editor, if any, replaces the numeric parameter sheet for a tool.
public enum EditorKind: Equatable {
    case photo, pdfPages, background, audio, video

    public static func kind(for tool: FileTool, selectionCount: Int) -> EditorKind? {
        guard selectionCount == 1 else { return nil }
        switch tool {
        case .cropImage, .resizeImage, .rotateImage, .flipImage, .grayscaleImage: return .photo
        case .backgroundImage: return .background
        case .extractPagesPDF, .rotatePDF: return .pdfPages
        case .trimAudio: return .audio
        case .trimVideo, .cropVideo: return .video
        default: return nil
        }
    }
}

/// Hands editor exports to the shared job queue so they show up in the same
/// HUD as everything else. `work` runs off the main thread, reports progress
/// 0...1, and should check `Task.isCancelled` (or throw `CancellationError`).
@MainActor
public final class EditorExporter {
    private let jobQueue: JobQueue
    private let showHUD: () -> Void

    public init(jobQueue: JobQueue, showHUD: @escaping () -> Void) {
        self.jobQueue = jobQueue
        self.showHUD = showHUD
    }

    public func export(displayName: String, icon: String,
                       work: @escaping @Sendable (@escaping @Sendable (Double) -> Void) async throws -> ConversionResult) {
        let job = Job(displayName: displayName, icon: icon)
        jobQueue.addJob(job) { [weak jobQueue] in
            do {
                let result = try await work { value in
                    Task { @MainActor in job.progress = value }
                }
                try Task.checkCancellation()
                job.state = .succeeded(message: result.warning ?? "Done", revealURL: result.outputURL)
                jobQueue?.autoRemoveAfterDelay(job)
            } catch is CancellationError {
                job.state = .cancelled
            } catch {
                job.state = .failed(error.localizedDescription)
            }
        }
        showHUD()
    }
}

/// An NSWindow that closes on Escape without saving.
final class EditorWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

/// Owns open editor windows. One window per file; reopening focuses it.
@MainActor
public final class EditorWindowManager: NSObject, NSWindowDelegate {
    private var windows: [String: NSWindow] = [:]
    private var closeHandlers: [ObjectIdentifier: () -> Void] = [:]

    func open<Content: View>(key: String, title: String, size: NSSize, onClose: (() -> Void)? = nil, @ViewBuilder content: (@escaping () -> Void) -> Content) {
        if let existing = windows[key] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = EditorWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: min(size.width, 640), height: min(size.height, 460))
        window.delegate = self
        window.contentView = NSHostingView(rootView: content { [weak window] in window?.close() })
        window.center()
        windows[key] = window
        if let onClose { closeHandlers[ObjectIdentifier(window)] = onClose }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        for (key, window) in windows where window === closing { windows[key] = nil }
        closeHandlers.removeValue(forKey: ObjectIdentifier(closing))?()
    }
}

/// Parses/prints editable time fields: "83.5", "1:23.5", "0:01:23.500".
public enum TimeText {
    public static func parse(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var total = 0.0
        for part in parts {
            guard let value = Double(part.replacingOccurrences(of: ",", with: ".")), value >= 0 else { return nil }
            total = total * 60 + value
        }
        return total
    }

    public static func format(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        let totalMillis = Int((clamped * 1000).rounded())
        let h = totalMillis / 3_600_000
        let m = (totalMillis / 60_000) % 60
        let s = (totalMillis / 1000) % 60
        let ms = totalMillis % 1000
        return h > 0 ? String(format: "%d:%02d:%02d.%03d", h, m, s, ms) : String(format: "%d:%02d.%03d", m, s, ms)
    }
}

/// Start/end of a trim, with the invariants every editor needs.
public struct TrimRange: Equatable {
    public static let minimumLength = 0.05
    public private(set) var start: Double
    public private(set) var end: Double
    public let duration: Double

    public init(duration: Double) {
        self.duration = max(duration, 0)
        start = 0
        end = self.duration
    }

    public var length: Double { end - start }

    public mutating func setStart(_ value: Double) {
        start = min(max(value, 0), max(end - Self.minimumLength, 0))
    }

    public mutating func setEnd(_ value: Double) {
        end = max(min(value, duration), min(start + Self.minimumLength, duration))
    }

    /// True when the selection is the whole file.
    public var isFull: Bool { start <= 0.0005 && end >= duration - 0.0005 }
}
