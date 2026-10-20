import AppKit

/// The keyboard-only flow: select a file in Finder, press Enter to open
/// the Convert wheel (no drag involved), arrow keys move the highlight,
/// Enter applies, Escape cancels, Command/Control switch to the other
/// wheels — same keys as the drag flow, just without a drag.
///
/// Getting Finder's selection means sending it an Apple Event
/// (`NSAppleScript`), which prompts for "Automation" permission the first
/// time, separately from Accessibility/Input Monitoring — explained in
/// onboarding. If denied, this flow simply does nothing (logged), rather
/// than failing loudly for something the user may not even want.
final class FinderKeyboardController {
    private static let returnKeyCode: UInt16 = 36
    private static let escapeKeyCode: UInt16 = 53
    private static let leftArrow: UInt16 = 123
    private static let rightArrow: UInt16 = 124
    private static let downArrow: UInt16 = 125
    private static let upArrow: UInt16 = 126

    private let wheelController: WheelPanelController
    private let settingsStore: SettingsStore

    private var keyMonitor: Any?
    private var flagsMonitor: Any?
    private var isActive = false
    private var activeURLs: [URL] = []
    private var previousFlags: NSEvent.ModifierFlags = []

    init(wheelController: WheelPanelController, settingsStore: SettingsStore) {
        self.wheelController = wheelController
        self.settingsStore = settingsStore
        start()
    }

    deinit {
        [keyMonitor, flagsMonitor].forEach { monitor in
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }

    private func start() {
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
        }
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        if !isActive {
            guard event.keyCode == Self.returnKeyCode else { return }
            tryOpenFromFinderSelection()
            return
        }

        switch event.keyCode {
        case Self.escapeKeyCode:
            close()
        case Self.returnKeyCode:
            apply()
        case Self.leftArrow, Self.upArrow:
            move(by: -1)
        case Self.rightArrow, Self.downArrow:
            move(by: 1)
        default:
            break
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        guard isActive else { return }
        let trackedFlags: NSEvent.ModifierFlags = [.shift, .command, .control, .option]
        let newFlags = event.modifierFlags.intersection(trackedFlags)
        let pressedDown = newFlags.subtracting(previousFlags)
        previousFlags = newFlags

        guard !pressedDown.isEmpty else { return }
        for (kind, key) in settingsStore.triggerKeyMapping where pressedDown.contains(key.modifierFlag) {
            wheelController.switchKind(kind, sourceURLs: activeURLs, disabledFormats: settingsStore.disabledFormatIdentifiers)
            wheelController.model.hoveredIndex = wheelController.model.segments.isEmpty ? nil : 0
        }
    }

    private func tryOpenFromFinderSelection() {
        guard !wheelController.isVisible else { return }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else { return }
        guard let urls = Self.currentFinderSelection(), !urls.isEmpty else { return }

        activeURLs = urls
        isActive = true
        wheelController.show(at: NSEvent.mouseLocation, kind: .convert, sourceURLs: urls, disabledFormats: settingsStore.disabledFormatIdentifiers)
        wheelController.model.hoveredIndex = wheelController.model.segments.isEmpty ? nil : 0
    }

    private func move(by delta: Int) {
        let count = wheelController.model.segments.count
        guard count > 0 else { return }
        let current = wheelController.model.hoveredIndex ?? 0
        wheelController.model.hoveredIndex = ((current + delta) % count + count) % count
    }

    private func apply() {
        guard let index = wheelController.model.hoveredIndex, wheelController.model.segments.indices.contains(index) else {
            close()
            return
        }
        let segment = wheelController.model.segments[index]
        let kind = wheelController.model.kind
        let urls = activeURLs
        close()
        wheelController.onDrop?(kind, segment, urls)
    }

    private func close() {
        isActive = false
        activeURLs = []
        wheelController.hide()
    }

    /// Queries Finder's current selection via Apple Events. Synchronous
    /// (Apple Events are) and fast for a plain selection query — fine to
    /// run on the main thread in direct response to a key press.
    private static func currentFinderSelection() -> [URL]? {
        let script = """
        tell application "Finder"
            set theSelection to selection
            set thePaths to {}
            repeat with anItem in theSelection
                set end of thePaths to (POSIX path of (anItem as alias))
            end repeat
            return thePaths
        end tell
        """
        guard let appleScript = NSAppleScript(source: script) else { return nil }
        var error: NSDictionary?
        let result = appleScript.executeAndReturnError(&error)
        if let error {
            NSLog("\(AppIdentity.name): couldn't read Finder's selection (Automation permission may be needed) — \(error)")
            return nil
        }

        var urls: [URL] = []
        if result.numberOfItems > 0 {
            for index in 1...result.numberOfItems {
                if let path = result.atIndex(index)?.stringValue {
                    urls.append(URL(fileURLWithPath: path))
                }
            }
        } else if let path = result.stringValue {
            urls.append(URL(fileURLWithPath: path))
        }
        return urls.isEmpty ? nil : urls
    }
}
