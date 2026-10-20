import AppKit

final class WheelPanelController {
    let model = WheelViewModel(kind: .convert)
    var onDrop: ((WheelKind, WheelSegment, [URL]) -> Void)?

    private var panel: NSPanel?
    private var hostingView: WheelHostingView?

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func show(at screenPoint: NSPoint, kind: WheelKind, sourceURLs: [URL], disabledFormats: Set<String> = []) {
        hostingView?.isArmed = true
        model.setKind(kind, sourceURLs: sourceURLs, disabledFormats: disabledFormats)
        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel, near: screenPoint)
        panel.orderFrontRegardless()
    }

    func switchKind(_ kind: WheelKind, sourceURLs: [URL], disabledFormats: Set<String> = []) {
        model.setKind(kind, sourceURLs: sourceURLs, disabledFormats: disabledFormats)
    }

    func hide() {
        panel?.orderOut(nil)
        model.hoveredIndex = nil
    }

    /// Escape: disarm the drag destination immediately (so a drop that
    /// lands before the window finishes ordering out is still rejected),
    /// then hide.
    func cancel() {
        hostingView?.isArmed = false
        hide()
    }

    private func makePanel() -> NSPanel {
        let size = WheelGeometry.panelSize
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .popUpMenu
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        let hostingView = WheelHostingView(rootView: WheelView(model: model))
        hostingView.model = model
        hostingView.onDrop = { [weak self] urls, index in
            guard let self else { return }
            let segment = self.model.segments[index]
            self.onDrop?(self.model.kind, segment, urls)
            self.hide()
        }
        panel.contentView = hostingView
        self.hostingView = hostingView
        return panel
    }

    private func position(_ panel: NSPanel, near point: NSPoint) {
        let size = WheelGeometry.panelSize
        var origin = NSPoint(x: point.x - size / 2, y: point.y - size / 2)

        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main {
            let frame = screen.visibleFrame
            origin.x = min(max(origin.x, frame.minX), frame.maxX - size)
            origin.y = min(max(origin.y, frame.minY), frame.maxY - size)
        }

        panel.setFrameOrigin(origin)
    }
}
