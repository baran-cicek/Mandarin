import SwiftUI

private struct WaveformShape: View {
    let peaks: [Float]
    var body: some View {
        Canvas { context, size in
            guard !peaks.isEmpty else { return }
            let mid = size.height / 2
            let step = size.width / CGFloat(peaks.count)
            var path = Path()
            for (i, peak) in peaks.enumerated() {
                let x = CGFloat(i) * step
                let h = max(CGFloat(min(peak, 1)) * (size.height / 2 - 2), 0.5)
                path.move(to: CGPoint(x: x, y: mid - h))
                path.addLine(to: CGPoint(x: x, y: mid + h))
            }
            context.stroke(path, with: .color(.accentColor), lineWidth: max(step, 1))
        }
    }
}

struct AudioEditorView: View {
    @ObservedObject var model: AudioEditorModel
    @ObservedObject var player: MediaPreviewPlayer
    let onSave: () -> Void
    let onSplit: () -> Void
    let onCancel: () -> Void

    init(model: AudioEditorModel, onSave: @escaping () -> Void, onSplit: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.model = model; self.player = model.player
        self.onSave = onSave; self.onSplit = onSplit; self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor))
                TrimTimeline(
                    duration: model.duration, start: model.trim.start, end: model.trim.end, playhead: player.playhead,
                    drag: model.drag,
                    onStart: { model.setStart($0) }, onEnd: { model.setEnd($0) }, onSeek: { player.seek(to: $0) }
                ) {
                    WaveformShape(peaks: model.peaks)
                }
                if model.waveformLoading && model.peaks.isEmpty { ProgressView("Reading waveform…").controlSize(.small) }
                if let error = model.waveformError { Text(error).font(.caption).foregroundStyle(.secondary) }
            }
            .frame(height: 150)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Waveform with trim handles")

            HStack {
                Button { model.togglePlayback() } label: {
                    Label(player.isPlaying ? "Pause" : "Play Selection", systemImage: player.isPlaying ? "pause.fill" : "play.fill")
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(player.error != nil)
                Text(TimeText.format(player.playhead) + " / " + TimeText.format(model.duration))
                    .font(.body.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
            }
            if let error = player.error { Text(error).font(.caption).foregroundStyle(.orange) }

            TrimFields(start: model.trim.start, end: model.trim.end, playhead: player.playhead,
                       onStart: { model.setStart($0) }, onEnd: { model.setEnd($0) })

            Divider()
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Fade in")
                    Slider(value: $model.fadeIn, in: 0...max(min(model.trim.length / 2, 30), 0.1)).accessibilityLabel("Fade in")
                    Text(String(format: "%.1f s", model.fadeIn)).font(.caption.monospacedDigit()).frame(width: 48, alignment: .trailing)
                }
                GridRow {
                    Text("Fade out")
                    Slider(value: $model.fadeOut, in: 0...max(min(model.trim.length / 2, 30), 0.1)).accessibilityLabel("Fade out")
                    Text(String(format: "%.1f s", model.fadeOut)).font(.caption.monospacedDigit()).frame(width: 48, alignment: .trailing)
                }
                GridRow {
                    Text("Volume")
                    Slider(value: $model.volume, in: 0...2).accessibilityLabel("Volume")
                    Text("\(Int(model.volume * 100))%").font(.caption.monospacedDigit()).frame(width: 48, alignment: .trailing)
                }
            }
            Text("Fades and volumes above 100% are applied when you save; the preview plays at up to 100% and without fades.")
                .font(.caption).foregroundStyle(.secondary)

            Spacer(minLength: 0)
            HStack {
                Button("Split at Playhead…", action: onSplit)
                    .disabled(!model.canSplit)
                    .help("Saves two files: before and after the playhead")
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save Copy", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.hasChanges)
            }
        }
        .padding(18)
        .frame(minWidth: 680, minHeight: 440)
    }
}
