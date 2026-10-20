import SwiftUI

struct PhotoEditorView: View {
    @ObservedObject var model: PhotoEditorModel
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                canvas
                Divider()
                inspector.frame(width: 270)
            }
            Divider()
            footer
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    // MARK: Canvas

    private var canvas: some View {
        GeometryReader { geometry in
            let size = model.showOriginal ? model.originalSize : model.orientedSize
            let display = CropGeometry.fit(content: size, in: geometry.size)
            ZStack {
                Color(nsColor: .underPageBackgroundColor)
                Image(nsImage: model.showOriginal ? model.originalImage : model.preview)
                    .resizable()
                    .interpolation(.medium)
                    .frame(width: display.width, height: display.height)
                    .position(x: display.midX, y: display.midY)
                    .accessibilityLabel(model.showOriginal ? "Original image" : "Edited preview")
                if !model.showOriginal {
                    CropOverlay(
                        imageSize: model.orientedSize, crop: model.cropRect, display: display,
                        onDrag: { model.dragChanged(start: $0, current: $1, display: display) },
                        onEnd: { model.dragEnded() },
                        onNudge: { model.nudgeCrop(dx: $0, dy: $1) }
                    )
                }
            }
        }
        .frame(minWidth: 440, minHeight: 360)
    }

    // MARK: Inspector

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                section("Crop") {
                    Picker("Aspect ratio", selection: Binding(get: { model.aspect }, set: { model.setAspect($0) })) {
                        ForEach(AspectPreset.allCases) { Text($0.title).tag($0) }
                    }
                    HStack {
                        intField("X", value: Int(model.cropRect.minX)) { model.setCrop(x: $0) }
                        intField("Y", value: Int(model.cropRect.minY)) { model.setCrop(y: $0) }
                    }
                    HStack {
                        intField("Width", value: Int(model.cropRect.width)) { model.setCrop(width: $0) }
                        intField("Height", value: Int(model.cropRect.height)) { model.setCrop(height: $0) }
                    }
                    Button("Reset crop") { model.resetCrop() }
                }

                section("Rotate and flip") {
                    HStack {
                        Button { model.rotate(clockwise: false) } label: { Image(systemName: "rotate.left") }
                            .accessibilityLabel("Rotate left")
                        Button { model.rotate(clockwise: true) } label: { Image(systemName: "rotate.right") }
                            .accessibilityLabel("Rotate right")
                        Button { model.flip(horizontal: true) } label: { Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right") }
                            .accessibilityLabel("Flip horizontally")
                        Button { model.flip(horizontal: false) } label: { Image(systemName: "arrow.up.and.down.righttriangle.up.righttriangle.down") }
                            .accessibilityLabel("Flip vertically")
                    }
                }

                section("Size") {
                    Toggle("Resize on save", isOn: Binding(get: { model.resizeEnabled }, set: { model.setResizeEnabled($0) }))
                    if model.resizeEnabled {
                        HStack {
                            intField("Width", value: model.targetWidth) { model.setTargetWidth($0) }
                            intField("Height", value: model.targetHeight) { model.setTargetHeight($0) }
                        }
                        Toggle("Keep proportions", isOn: $model.linkRatio)
                    }
                }

                section("Adjust") {
                    sliderRow("Brightness", value: $model.edits.brightness, range: -0.5...0.5, neutral: 0)
                    sliderRow("Contrast", value: $model.edits.contrast, range: 0.5...1.5, neutral: 1)
                    sliderRow("Saturation", value: $model.edits.saturation, range: 0...2, neutral: 1)
                    Toggle("Grayscale", isOn: $model.edits.grayscale)
                }

                Button("Reset everything") { model.resetAll() }
            }
            .padding(16)
        }
    }

    private var footer: some View {
        HStack {
            Toggle(isOn: $model.showOriginal) {
                Label("Show original", systemImage: "square.on.square")
            }
            .toggleStyle(.button)
            .accessibilityLabel("Show original")
            .accessibilityHint("Switches between the original and the edited version")
            Text("\(Int(model.cropRect.width)) × \(Int(model.cropRect.height)) px"
                 + (model.resizeEnabled ? " → \(model.targetWidth) × \(model.targetHeight)" : ""))
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Cancel", action: onCancel)
            Button("Save Copy", action: onSave)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.hasChanges)
        }
        .padding(12)
    }

    // MARK: Pieces

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    private func intField(_ label: String, value: Int, onCommit: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, value: Binding(get: { value }, set: { onCommit($0) }), formatter: Self.integerFormatter)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(label)
        }
    }

    private func sliderRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, neutral: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption)
                Spacer()
                Text(String(format: "%+.2f", value.wrappedValue - neutral)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
                .accessibilityLabel(label)
        }
    }

    private static let integerFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .none
        f.minimum = 0
        return f
    }()
}
