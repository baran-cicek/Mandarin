import AppKit
import SwiftUI

/// Renders editor views offscreen so the self-tests can check that they lay
/// out and draw something (and optionally save PNGs for a human to look at).
@MainActor
public enum EditorSnapshots {
    static func render<V: View>(_ view: V, size: NSSize) -> NSBitmapImageRep? {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        // Let SwiftUI run its layout passes.
        for _ in 0..<5 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }

    public static func photoEditor(_ model: PhotoEditorModel, size: NSSize = NSSize(width: 1020, height: 640)) -> NSBitmapImageRep? {
        render(PhotoEditorView(model: model, onSave: {}, onCancel: {}), size: size)
    }

    public static func pdfPages(_ model: PDFPagesModel, size: NSSize = NSSize(width: 860, height: 600)) -> NSBitmapImageRep? {
        render(PDFPagesView(model: model, onSaveAll: {}, onExtract: {}, onCancel: {}), size: size)
    }

    public static func backgroundEditor(_ model: BackgroundEditorModel, size: NSSize = NSSize(width: 960, height: 600)) -> NSBitmapImageRep? {
        render(BackgroundEditorView(model: model, onSave: {}, onCancel: {}), size: size)
    }

    public static func audioEditor(_ model: AudioEditorModel, size: NSSize = NSSize(width: 760, height: 480)) -> NSBitmapImageRep? {
        render(AudioEditorView(model: model, onSave: {}, onSplit: {}, onCancel: {}), size: size)
    }

    public static func videoEditor(_ model: VideoEditorModel, size: NSSize = NSSize(width: 860, height: 700)) -> NSBitmapImageRep? {
        render(VideoEditorView(model: model, onSave: {}, onCancel: {}), size: size)
    }
}
