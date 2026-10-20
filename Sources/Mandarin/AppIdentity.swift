import Foundation

/// The single place the product name and bundle identifier live in code.
/// To rename the app: change these two values, `CFBundleName`,
/// `CFBundleDisplayName`, `CFBundleExecutable` and `CFBundleIdentifier` in
/// `Resources/Info.plist`, and the README title. A self-test fails if they
/// drift apart.
public enum AppIdentity {
    public static let name = "Mandarin"
    public static let bundleID = "dev.mandarin.app"
}
