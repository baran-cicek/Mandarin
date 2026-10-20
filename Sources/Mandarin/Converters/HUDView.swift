import AppKit
import SwiftUI

struct HUDView: View {
    @ObservedObject var jobQueue: JobQueue

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(jobQueue.jobs) { job in
                HUDRow(job: job, onCancel: { jobQueue.cancel(job) }, onDismiss: { jobQueue.remove(job) })
            }
        }
        .padding(10)
        .frame(width: 300, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct HUDRow: View {
    @ObservedObject var job: Job
    let onCancel: () -> Void
    let onDismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: job.icon)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(job.displayName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)

                switch job.state {
                case .running:
                    ProgressView(value: job.progress)
                        .progressViewStyle(.linear)
                case .succeeded(let message, _):
                    Text(message).font(.caption2).foregroundStyle(.secondary)
                case .failed(let message):
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                case .cancelled:
                    Text("Cancelled").font(.caption2).foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)
            trailingControl
        }
        .animation(reduceMotion ? nil : .default, value: job.progress)
    }

    @ViewBuilder
    private var trailingControl: some View {
        switch job.state {
        case .running:
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Cancel")

        case .succeeded(_, let revealURL):
            if let revealURL {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([revealURL])
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.green)
                .accessibilityLabel("Reveal in Finder")
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

        case .failed:
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Dismiss")
            }

        case .cancelled:
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Dismiss")
        }
    }
}
