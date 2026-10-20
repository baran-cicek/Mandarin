import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settingsStore = SettingsStore()
    private var statusBarController: StatusBarController?
    private var onboardingWindow: NSWindow?
    private let wheelController = WheelPanelController()
    private var dragWatcher: DragWatcher?
    private var finderKeyboardController: FinderKeyboardController?
    private var jobQueue: JobQueue!
    private var hudController: HUDController!
    private let floatController = FloatPanelController()
    private var fileActionRunner: FileActionRunner!
    private var fileToolRunner: FileToolRunner!
    private let toolParameterWindowController = ToolParameterWindowController()
    private var editorCoordinator: EditorCoordinator!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ExternalTool.checkAllAtStartup()

        statusBarController = StatusBarController(settingsStore: settingsStore,
                                                    onShowPermissions: { [weak self] in
            self?.showOnboardingWindow()
        })

        jobQueue = JobQueue(settingsStore: settingsStore)
        hudController = HUDController(jobQueue: jobQueue)
        fileActionRunner = FileActionRunner(jobQueue: jobQueue, floatController: floatController)
        fileToolRunner = FileToolRunner(jobQueue: jobQueue)
        editorCoordinator = EditorCoordinator(
            jobQueue: jobQueue, settingsStore: settingsStore,
            showHUD: { [weak self] in self?.hudController.show(near: NSEvent.mouseLocation) },
            reportError: { [weak self] name, message in
                guard let self else { return }
                self.jobQueue.reportFailure(displayName: name, message: message)
                self.hudController.show(near: NSEvent.mouseLocation)
            }
        )

        wheelController.onDrop = { [weak self] kind, segment, urls in
            guard let self else { return }
            switch (kind, segment.outputType, segment.fileAction, segment.fileTool) {
            case (.convert, let outputType?, _, _):
                self.jobQueue.convert(urls: urls, to: outputType)
                self.hudController.show(near: NSEvent.mouseLocation)
            case (.fileActions, _, let action?, _):
                // Copy/Move show a modal NSOpenPanel; deferring to the next
                // run-loop tick lets the OS drag session (owned by another
                // app, e.g. Finder) finish tearing down first instead of
                // nesting a modal panel inside its drag-completion callback.
                DispatchQueue.main.async {
                    self.fileActionRunner.perform(action, on: urls)
                    self.hudController.show(near: NSEvent.mouseLocation)
                }
            case (.fileTools, _, _, let tool?):
                // Same deferral as File Actions — several tools show a
                // parameter sheet, which is itself a window and shouldn't
                // be nested inside the drag source's completion callback.
                DispatchQueue.main.async {
                    if self.editorCoordinator.open(tool, urls: urls) { return }
                    if tool.parameters.isEmpty {
                        self.fileToolRunner.perform(tool, on: urls, parameters: ToolParameterValues())
                        self.hudController.show(near: NSEvent.mouseLocation)
                    } else {
                        let fileName = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) items"
                        self.toolParameterWindowController.show(
                            tool: tool, fileName: fileName,
                            onApply: { values in
                                self.fileToolRunner.perform(tool, on: urls, parameters: values)
                                self.hudController.show(near: NSEvent.mouseLocation)
                            },
                            onCancel: {}
                        )
                    }
                }
            default:
                let names = urls.map { $0.lastPathComponent }.joined(separator: ", ")
                NSLog("\(AppIdentity.name): unhandled drop — \(kind.title) → \(segment.title) on [\(names)]")
            }
        }
        dragWatcher = DragWatcher(wheelController: wheelController, settingsStore: settingsStore)
        finderKeyboardController = FinderKeyboardController(wheelController: wheelController, settingsStore: settingsStore)

        if !PermissionsManager.shared.hasAllPermissions {
            showOnboardingWindow()
        }
    }

    func showOnboardingWindow() {
        if let window = onboardingWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = PermissionsView(onContinue: { [weak self] in
            self?.onboardingWindow?.close()
        })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(AppIdentity.name) Setup"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        settingsStore.save()
    }
}
