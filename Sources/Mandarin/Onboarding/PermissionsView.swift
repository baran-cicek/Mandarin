import Combine
import SwiftUI

final class PermissionsStatus: ObservableObject {
    @Published var hasAccessibility = PermissionsManager.shared.hasAccessibilityPermission
    @Published var hasInputMonitoring = PermissionsManager.shared.hasInputMonitoringPermission

    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        hasAccessibility = PermissionsManager.shared.hasAccessibilityPermission
        hasInputMonitoring = PermissionsManager.shared.hasInputMonitoringPermission
    }

    deinit {
        timer?.invalidate()
    }
}

struct PermissionsView: View {
    let onContinue: () -> Void

    @ObservedObject private var status = PermissionsStatus()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 32))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading) {
                    Text("\(AppIdentity.name) needs two permissions")
                        .font(.headline)
                    Text("These let \(AppIdentity.name) watch for drags and key taps system-wide. Nothing leaves your Mac.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            permissionRow(
                symbol: "accessibility",
                title: "Accessibility",
                detail: "Lets \(AppIdentity.name) see when you're dragging a file and show the wheel near your cursor.",
                granted: status.hasAccessibility,
                openAction: { PermissionsManager.shared.requestAccessibilityPermission() }
            )

            permissionRow(
                symbol: "keyboard",
                title: "Input Monitoring",
                detail: "Lets \(AppIdentity.name) detect Shift/Command/Control taps while a drag is in progress.",
                granted: status.hasInputMonitoring,
                openAction: { PermissionsManager.shared.requestInputMonitoringPermission() }
            )

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle")
                    .font(.system(size: 20))
                    .frame(width: 24)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("One more, later").font(.body).bold()
                    Text("Selecting a file in Finder and pressing Return opens the wheel without a drag. The first time you do that, macOS will separately ask to let \(AppIdentity.name) control Finder — that's expected, just allow it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Continue") {
                    onContinue()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480, height: 420)
    }

    private func permissionRow(symbol: String, title: String, detail: String, granted: Bool, openAction: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body).bold()
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Open Settings…", action: openAction)
            }
        }
    }
}
