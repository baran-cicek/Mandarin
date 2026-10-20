import AppKit
import Combine
import SwiftUI

@MainActor
final class HUDController {
    private let jobQueue: JobQueue
    private var panel: NSPanel?
    private var cancellable: AnyCancellable?

    init(jobQueue: JobQueue) {
        self.jobQueue = jobQueue
        cancellable = jobQueue.$jobs.sink { [weak self] jobs in
            if jobs.isEmpty { self?.panel?.orderOut(nil) }
        }
    }

    func show(near point: NSPoint) {
        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel, near: point)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 10),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: HUDView(jobQueue: jobQueue))
        return panel
    }

    private func position(_ panel: NSPanel, near point: NSPoint) {
        let contentView = panel.contentView
        contentView?.layoutSubtreeIfNeeded()
        let fittingSize = contentView?.fittingSize ?? NSSize(width: 300, height: 80)
        panel.setContentSize(fittingSize)

        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else {
            return
        }
        let frame = screen.visibleFrame
        let origin = NSPoint(x: frame.maxX - fittingSize.width - 20, y: frame.minY + 20)
        panel.setFrameOrigin(origin)
    }
}
