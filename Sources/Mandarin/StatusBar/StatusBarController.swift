import AppKit

final class StatusBarController {
    private let statusItem: NSStatusItem
    private let settingsStore: SettingsStore
    private let onShowPermissions: () -> Void

    init(settingsStore: SettingsStore, onShowPermissions: @escaping () -> Void) {
        self.settingsStore = settingsStore
        self.onShowPermissions = onShowPermissions
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = MenuBarIcon.image()
        }

        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let statusLine = NSMenuItem(title: AppIdentity.name, action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())

        let permissionsItem = NSMenuItem(title: "Permissions…", action: #selector(showPermissions), keyEquivalent: "")
        permissionsItem.target = self
        menu.addItem(permissionsItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit \(AppIdentity.name)", action: #selector(NSApplication.terminate), keyEquivalent: "q")
        menu.addItem(quitItem)

        return menu
    }

    @objc private func showPermissions() {
        onShowPermissions()
    }

    @objc private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
