import AppKit
import CoreGraphics

/// Detects system-wide file/folder drags by polling the drag pasteboard's
/// changeCount while the left mouse button is down (there is no public
/// notification for "a drag started"), then opens the wheel on a modifier
/// key tap and keeps it open until drop or Escape.
///
/// Escape is polled via `CGEventSource.keyState`, not a global `.keyDown`
/// monitor: while Finder (or any app) is running its own drag-tracking loop,
/// Escape is AppKit's built-in "cancel this drag" key, and the source app's
/// tracking loop consumes it locally — the system only re-broadcasts it to
/// other apps' global `.keyDown` monitors once that tracking loop unwinds on
/// mouse-up, which is far too late. `CGEventSource.keyState` reads the raw
/// HID key state directly and isn't subject to that delay.
final class DragWatcher {
    private static let escapeKeyCode: CGKeyCode = 53
    /// How long a press has to sit still before a drag that starts after
    /// it auto-opens the Convert wheel — "hold briefly before dragging,"
    /// the trackpad-friendly alternative to tapping a modifier key.
    private static let holdToDragThreshold: TimeInterval = 0.45

    private let wheelController: WheelPanelController
    private let settingsStore: SettingsStore

    private var mouseMonitor: Any?
    private var flagsMonitor: Any?
    private var pollTimer: Timer?

    private var isMouseDown = false
    private var isDraggingFiles = false
    private var draggedURLs: [URL] = []
    private var baselineDragChangeCount = NSPasteboard(name: .drag).changeCount
    private var previousFlags: NSEvent.ModifierFlags = []
    private var mouseDownTime: Date?

    init(wheelController: WheelPanelController, settingsStore: SettingsStore) {
        self.wheelController = wheelController
        self.settingsStore = settingsStore
        start()
    }

    deinit {
        [mouseMonitor, flagsMonitor].forEach { monitor in
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        pollTimer?.invalidate()
    }

    private func start() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp]
        ) { [weak self] event in
            self?.handleMouse(event)
        }
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
    }

    private func handleMouse(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            isMouseDown = true
            mouseDownTime = Date()
            baselineDragChangeCount = NSPasteboard(name: .drag).changeCount
            startPolling()
        case .leftMouseUp:
            isMouseDown = false
            stopPolling()
            endDragSession()
        default:
            break
        }
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            self?.checkDragPasteboard()
            self?.checkEscape()
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func checkDragPasteboard() {
        guard isMouseDown, !isDraggingFiles else { return }
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != baselineDragChangeCount else { return }
        baselineDragChangeCount = pasteboard.changeCount

        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
              !urls.isEmpty else { return }
        isDraggingFiles = true
        draggedURLs = urls

        // Trackpad hold-to-drag: if the press already sat still long
        // enough before this drag started, open Convert automatically —
        // no modifier tap needed. A quick drag (no real hold) still
        // requires a modifier key, same as before.
        if let mouseDownTime, Date().timeIntervalSince(mouseDownTime) >= Self.holdToDragThreshold, !wheelController.isVisible {
            showWheel(for: .convert)
        }
    }

    private func checkEscape() {
        guard wheelController.isVisible else { return }
        guard CGEventSource.keyState(.combinedSessionState, key: Self.escapeKeyCode) else { return }
        NSLog("\(AppIdentity.name): Escape detected mid-drag — cancelling wheel immediately")
        wheelController.cancel()
    }

    private func endDragSession() {
        isDraggingFiles = false
        draggedURLs = []
        mouseDownTime = nil
        wheelController.hide()
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let trackedFlags: NSEvent.ModifierFlags = [.shift, .command, .control, .option]
        let newFlags = event.modifierFlags.intersection(trackedFlags)
        let pressedDown = newFlags.subtracting(previousFlags)
        previousFlags = newFlags

        guard isDraggingFiles, !pressedDown.isEmpty else { return }

        for (kind, key) in settingsStore.triggerKeyMapping where pressedDown.contains(key.modifierFlag) {
            showWheel(for: kind)
        }
    }

    private func showWheel(for kind: WheelKind) {
        if wheelController.isVisible {
            wheelController.switchKind(kind, sourceURLs: draggedURLs, disabledFormats: settingsStore.disabledFormatIdentifiers)
        } else {
            wheelController.show(at: NSEvent.mouseLocation, kind: kind, sourceURLs: draggedURLs, disabledFormats: settingsStore.disabledFormatIdentifiers)
        }
    }
}
