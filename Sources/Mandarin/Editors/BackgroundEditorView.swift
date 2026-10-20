import AppKit
import SwiftUI

extension RGB {
    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(r: Double(ns.redComponent), g: Double(ns.greenComponent), b: Double(ns.blueComponent))
    }
    var color: Color { Color(.sRGB, red: r, green: g, blue: b) }
}

private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 12
            for row in 0..<Int(size.height / cell) + 1 {
                for col in 0..<Int(size.width / cell) + 1 where (row + col) % 2 == 0 {
                    context.fill(Path(CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)), with: .color(.gray.opacity(0.25)))
                }
            }
        }
        .background(Color.gray.opacity(0.08))
    }
}

struct BackgroundEditorView: View {
    @ObservedObject var model: BackgroundEditorModel
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                canvas
                Divider()
                inspector.frame(width: 280)
            }
            Divider()
            HStack {
                if model.working { ProgressView().controlSize(.small); Text("Updating preview…").font(.caption).foregroundStyle(.secondary) }
                if let notice = model.notice { Label(notice, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save PNG Copy", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.hasChanges || model.notice != nil)
            }
            .padding(12)
        }
        .frame(minWidth: 760, minHeight: 500)
    }

    private var canvas: some View {
        GeometryReader { geometry in
            let display = CropGeometry.fit(content: model.pixelSize, in: geometry.size)
            ZStack {
                Checkerboard()
                Image(nsImage: model.preview)
                    .resizable()
                    .frame(width: display.width, height: display.height)
                    .position(x: display.midX, y: display.midY)
                    .accessibilityLabel("Preview of the image with the new background")
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                guard model.removalMode == .solid, display.contains(value.location) else { return }
                model.pickKey(atFraction: CGPoint(x: (value.location.x - display.minX) / display.width,
                                                  y: (value.location.y - display.minY) / display.height))
            })
        }
        .frame(minWidth: 440, minHeight: 360)
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Original background").font(.headline)
                    Picker("Original background", selection: $model.removalMode) {
                        ForEach(BackgroundEditorModel.RemovalMode.allCases.filter { $0 != .subject || model.subjectAvailable }) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    if model.removalMode == .solid {
                        ColorPicker("Background color", selection: Binding(get: { model.keyColor.color }, set: { model.keyColor = RGB($0) }), supportsOpacity: false)
                        Text("Click the image to pick the color.").font(.caption).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack { Text("Tolerance").font(.caption); Spacer(); Text("\(Int(model.tolerance * 100))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                            Slider(value: $model.tolerance, in: 0...0.6).accessibilityLabel("Tolerance")
                        }
                        Toggle("Only areas connected to the edges", isOn: $model.contiguous)
                    }
                    if model.removalMode == .subject {
                        Text("Keeps the main subject and removes the rest.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("New background").font(.headline)
                    Picker("New background", selection: $model.fillMode) {
                        ForEach(BackgroundEditorModel.FillMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if model.fillMode != .none {
                        ColorPicker(model.fillMode == .gradient ? "From" : "Color", selection: Binding(get: { model.fillColor.color }, set: { model.fillColor = RGB($0) }), supportsOpacity: false)
                    }
                    if model.fillMode == .gradient {
                        ColorPicker("To", selection: Binding(get: { model.gradientEnd.color }, set: { model.gradientEnd = RGB($0) }), supportsOpacity: false)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack { Text("Angle").font(.caption); Spacer(); Text("\(Int(model.gradientAngle))°").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                            Slider(value: $model.gradientAngle, in: 0...360, step: 5).accessibilityLabel("Gradient angle")
                        }
                    }
                }
                Text("The result is saved as a PNG next to the original; the original is never changed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
        }
    }
}
