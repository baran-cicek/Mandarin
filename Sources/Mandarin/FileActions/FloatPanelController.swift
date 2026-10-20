import AppKit
import SwiftUI

/// One small always-on-top preview panel per floated file. Escape closes
/// all of them (a dedicated monitor, only installed while at least one is
/// open — this isn't racing an active OS drag like the wheel's Escape, so
/// a plain global monitor is fine here); each panel's own close button
/// dismisses just that one.
@MainActor
final class FloatPanelController {
    private var panels: [NSPanel] = []
    private var escapeMonitor: Any?

    func showFloats(for urls: [URL]) {
        for url in urls {
            showPanel(for: url)
        }
    }

    private func showPanel(for url: URL) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false

        let model = FloatPreviewModel(url: url)
        let view = FloatPreviewView(model: model, onClose: { [weak self] in self?.close(panel) })
        panel.contentView = NSHostingView(rootView: view)

        position(panel)
        panels.append(panel)
        panel.orderFrontRegardless()
        installEscapeMonitorIfNeeded()
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let cascade = CGFloat(panels.count % 6) * 24
        panel.setFrameOrigin(NSPoint(x: frame.maxX - 200 - cascade, y: frame.minY + 20 + cascade))
    }

    private func close(_ panel: NSPanel) {
        panel.orderOut(nil)
        panels.removeAll { $0 === panel }
        if panels.isEmpty { removeEscapeMonitor() }
    }

    private func closeAll() {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        removeEscapeMonitor()
    }

    private func installEscapeMonitorIfNeeded() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor in self?.closeAll() }
        }
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
    }
}
