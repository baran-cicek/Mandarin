import SwiftUI

/// No `@main` here — this lives in the `Mandarin` library target so the
/// self-test executable can also `import Mandarin` (see
/// Tests/MandarinSelfTests and PROGRESS.md for why: plain executable
/// targets can't import each other under this CLT-only toolchain, but a
/// library target can be imported by any number of executables). The real
/// entry point is `Sources/MandarinAppExecutable/main.swift`, which calls
/// `MandarinApp.main()`.
public struct MandarinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    public init() {}

    public var body: some Scene {
        Settings {
            SettingsView(store: appDelegate.settingsStore)
        }
    }
}
