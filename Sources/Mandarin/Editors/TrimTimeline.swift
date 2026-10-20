import SwiftUI

/// Remembers which part of a timeline a drag started on (handles move, empty space seeks).
@MainActor
public final class TimelineDragState: ObservableObject {
    enum Mode { case start, end, seek }
    var mode: Mode?
    public init() {}
}

/// A strip with a draggable start handle, end handle and playhead over any
/// background (waveform, thumbnails). Keyboard/VoiceOver users use the
/// time fields next to it; the strip itself exposes adjustable elements too.
struct TrimTimeline<Background: View>: View {
    let duration: Double
    let start: Double
    let end: Double
    let playhead: Double
    @ObservedObject var drag: TimelineDragState
    let onStart: (Double) -> Void
    let onEnd: (Double) -> Void
    let onSeek: (Double) -> Void
    @ViewBuilder let background: () -> Background

    private let handleWidth: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let x: (Double) -> CGFloat = { duration > 0 ? CGFloat($0 / duration) * width : 0 }
            ZStack(alignment: .leading) {
                background()
                // dimmed outside the selection
                Rectangle().fill(Color.black.opacity(0.45)).frame(width: x(start)).allowsHitTesting(false)
                Rectangle().fill(Color.black.opacity(0.45)).frame(width: max(width - x(end), 0))
                    .offset(x: x(end)).allowsHitTesting(false)
                // selection frame
                Rectangle().stroke(Color.accentColor, lineWidth: 2)
                    .frame(width: max(x(end) - x(start), 2)).offset(x: x(start)).allowsHitTesting(false)
                handle(label: "Start").offset(x: x(start) - handleWidth / 2)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Start handle")
                    .accessibilityValue(TimeText.format(start))
                    .accessibilityAdjustableAction { direction in
                        let step = max(duration / 200, 0.05)
                        onStart(start + (direction == .increment ? step : -step))
                    }
                handle(label: "End").offset(x: x(end) - handleWidth / 2)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("End handle")
                    .accessibilityValue(TimeText.format(end))
                    .accessibilityAdjustableAction { direction in
                        let step = max(duration / 200, 0.05)
                        onEnd(end + (direction == .increment ? step : -step))
                    }
                Rectangle().fill(Color.white).frame(width: 2).shadow(radius: 1)
                    .offset(x: x(playhead) - 1).allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if drag.mode == nil {
                            let s = x(start), e = x(end), sx = value.startLocation.x
                            let nearStart = abs(sx - s) <= 14, nearEnd = abs(sx - e) <= 14
                            if nearStart && nearEnd { drag.mode = sx < (s + e) / 2 ? .start : .end }
                            else if nearStart { drag.mode = .start }
                            else if nearEnd { drag.mode = .end }
                            else { drag.mode = .seek }
                        }
                        let time = Double(min(max(value.location.x, 0), width) / width) * duration
                        switch drag.mode {
                        case .start: onStart(time)
                        case .end: onEnd(time)
                        case .seek, .none: onSeek(time)
                        }
                    }
                    .onEnded { _ in drag.mode = nil }
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func handle(label: String) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.accentColor)
            .frame(width: handleWidth)
            .overlay(Capsule().fill(Color.white.opacity(0.9)).frame(width: 2, height: 18))
    }
}

/// Start/end text fields plus "set to playhead" buttons, shared by the audio and video editors.
struct TrimFields: View {
    let start: Double
    let end: Double
    let playhead: Double
    let onStart: (Double) -> Void
    let onEnd: (Double) -> Void

    var body: some View {
        HStack(spacing: 14) {
            timeField("Start", value: start, set: onStart)
            Button("Start = Playhead") { onStart(playhead) }
                .keyboardShortcut("[", modifiers: .command)
            timeField("End", value: end, set: onEnd)
            Button("End = Playhead") { onEnd(playhead) }
                .keyboardShortcut("]", modifiers: .command)
            VStack(alignment: .leading, spacing: 2) {
                Text("Length").font(.caption).foregroundStyle(.secondary)
                Text(TimeText.format(end - start)).font(.body.monospacedDigit())
            }
        }
    }

    private func timeField(_ label: String, value: Double, set: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TimeTextField(label: label, value: value, onCommit: set)
        }
    }
}

/// A text field that commits parsed times on Return/focus loss and restores the old text on bad input.
struct TimeTextField: View {
    let label: String
    let value: Double
    let onCommit: (Double) -> Void
    @ObservedObject private var draft = DraftText()

    var body: some View {
        TextField(label, text: Binding(get: { draft.text ?? TimeText.format(value) }, set: { draft.text = $0 }), onEditingChanged: { editing in
            if !editing { commit() }
        }, onCommit: commit)
        .textFieldStyle(.roundedBorder)
        .font(.body.monospacedDigit())
        .frame(width: 110)
        .accessibilityLabel("\(label) time")
        .accessibilityHint("Type a time like 1:23.5 or 83.5 seconds")
    }

    private func commit() {
        if let text = draft.text, let seconds = TimeText.parse(text) { onCommit(seconds) }
        draft.text = nil
    }

    final class DraftText: ObservableObject { @Published var text: String? }
}
