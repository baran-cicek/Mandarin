import AVFoundation
import AppKit
import SwiftUI

/// Hosts an AVPlayerLayer; no playback chrome, the editor draws its own.
struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        layer.frame = view.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(layer)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct VideoEditorView: View {
    @ObservedObject var model: VideoEditorModel
    @ObservedObject var player: MediaPreviewPlayer
    let onSave: () -> Void
    let onCancel: () -> Void

    init(model: VideoEditorModel, onSave: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.model = model; self.player = model.player; self.onSave = onSave; self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            preview
                .frame(minHeight: 240)
            if let error = player.error { Text(error).font(.caption).foregroundStyle(.orange) }

            TrimTimeline(
                duration: model.info.duration, start: model.trim.start, end: model.trim.end, playhead: player.playhead,
                drag: model.drag,
                onStart: { model.setStart($0) }, onEnd: { model.setEnd($0) }, onSeek: { player.seek(to: $0) }
            ) {
                HStack(spacing: 0) {
                    ForEach(0..<VideoEditorModel.thumbnailCount, id: \.self) { index in
                        ZStack {
                            Color(nsColor: .controlBackgroundColor)
                            if let image = model.thumbnails[index] {
                                Image(nsImage: image).resizable().scaledToFill()
                            }
                        }
                        .clipped()
                    }
                }
            }
            .frame(height: 64)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Video timeline with trim handles")

            HStack(spacing: 14) {
                Button { model.togglePlayback() } label: {
                    Label(player.isPlaying ? "Pause" : "Play Selection", systemImage: player.isPlaying ? "pause.fill" : "play.fill")
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(player.error != nil)
                Text(TimeText.format(player.playhead) + " / " + TimeText.format(model.info.duration))
                    .font(.body.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
            }

            TrimFields(start: model.trim.start, end: model.trim.end, playhead: player.playhead,
                       onStart: { model.setStart($0) }, onEnd: { model.setEnd($0) })

            Divider()
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Crop picture", isOn: $model.cropEnabled)
                    if model.cropEnabled {
                        HStack {
                            Picker("Aspect ratio", selection: Binding(get: { model.aspect }, set: { model.setAspect($0) })) {
                                ForEach(AspectPreset.allCases) { Text($0.title).tag($0) }
                            }
                            .frame(width: 200)
                            Button("Reset") { model.resetCrop() }
                        }
                        HStack {
                            field("X", Int(model.cropRect.minX)) { model.setCrop(x: $0) }
                            field("Y", Int(model.cropRect.minY)) { model.setCrop(y: $0) }
                            field("Width", Int(model.cropRect.width)) { model.setCrop(width: $0) }
                            field("Height", Int(model.cropRect.height)) { model.setCrop(height: $0) }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Fast cut (no re-encoding)", isOn: $model.fastCut)
                        .disabled(model.cropEnabled)
                    Text(model.plan.isLossless
                         ? "Lossless. The start may snap to the nearest earlier keyframe."
                         : "Re-encodes for an exact cut. Takes longer.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save Copy", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.hasChanges)
            }
        }
        .padding(18)
        .frame(minWidth: 760, minHeight: 640)
    }

    private var preview: some View {
        GeometryReader { geometry in
            let display = CropGeometry.fit(content: model.info.size, in: geometry.size)
            ZStack {
                Color.black
                PlayerLayerView(player: player.player)
                    .accessibilityLabel("Video preview")
                if model.cropEnabled {
                    CropOverlay(
                        imageSize: model.info.size, crop: model.cropRect, display: display,
                        onDrag: { model.dragChanged(start: $0, current: $1, display: display) },
                        onEnd: { model.dragEnded() },
                        onNudge: { model.nudgeCrop(dx: $0, dy: $1) }
                    )
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func field(_ label: String, _ value: Int, _ commit: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, value: Binding(get: { value }, set: commit), formatter: Self.formatter)
                .textFieldStyle(.roundedBorder).frame(width: 78)
                .accessibilityLabel("Crop \(label)")
        }
    }

    private static let formatter: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .none; f.minimum = 0; return f
    }()
}
