import Foundation

/// One HUD row. Covers both image conversions and File Actions (Copy,
/// Move, AirDrop, ...) so both show up in the same place — "No silent
/// failures" applies equally to either.
///
/// Public (along with `JobQueue`/`SettingsStore`) so the headless
/// `MandarinConvert` CLI can drive the exact same queue a real drop uses —
/// see Tests/../MandarinConvert and PROGRESS.md.
@MainActor
public final class Job: ObservableObject, Identifiable {
    public enum State: Equatable {
        case running
        case succeeded(message: String, revealURL: URL?)
        case failed(String)
        case cancelled
    }

    public let id = UUID()
    /// What to show as the row's title — a filename for a single file, or
    /// something like "3 items" for an action spanning a whole selection.
    public let displayName: String
    public let icon: String

    @Published public var progress: Double = 0
    @Published public var state: State = .running

    init(displayName: String, icon: String) {
        self.displayName = displayName
        self.icon = icon
    }
}
