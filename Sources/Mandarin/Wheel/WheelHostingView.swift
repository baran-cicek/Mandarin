import AppKit
import SwiftUI

final class WheelHostingView: NSHostingView<WheelView> {
    var model: WheelViewModel!
    var onDrop: (([URL], Int) -> Void)?

    /// Set to false the instant Escape cancels the wheel, so a drop that
    /// arrives before the window finishes ordering out is still rejected —
    /// window visibility alone isn't a fast-enough guarantee during an
    /// active OS drag session.
    var isArmed = true

    required init(rootView: WheelView) {
        super.init(rootView: rootView)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func segmentIndex(for sender: NSDraggingInfo) -> Int? {
        guard isArmed else { return nil }
        let point = convert(sender.draggingLocation, from: nil)
        return WheelGeometry.segmentIndex(at: point, count: model.segments.count)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        model.hoveredIndex = segmentIndex(for: sender)
        return isArmed ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        model.hoveredIndex = segmentIndex(for: sender)
        return segmentIndex(for: sender) != nil ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        model.hoveredIndex = nil
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        segmentIndex(for: sender) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard isArmed else {
            NSLog("\(AppIdentity.name): drop rejected — wheel was cancelled")
            return false
        }
        guard let index = segmentIndex(for: sender) else { return false }
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        onDrop?(urls, index)
        return true
    }
}
