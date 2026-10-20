import AppKit
import SwiftUI

/// Collected values from a `ToolParameterSheet` — numbers and text keyed
/// by each `ToolParameter`'s `key`.
public struct ToolParameterValues {
    public var numbers: [String: Double] = [:]
    public var strings: [String: String] = [:]

    public init() {}
    public func number(_ key: String) -> Double { numbers[key] ?? 0 }
    public func string(_ key: String) -> String { strings[key] ?? "" }
}

final class ToolParameterSheetModel: ObservableObject {
    let tool: FileTool
    let fileName: String
    @Published var numbers: [String: Double] = [:]
    @Published var strings: [String: String] = [:]

    init(tool: FileTool, fileName: String) {
        self.tool = tool
        self.fileName = fileName
        for parameter in tool.parameters {
            switch parameter {
            case .number(let key, _, let defaultValue, _):
                numbers[key] = defaultValue
            case .text(let key, _, let defaultValue):
                strings[key] = defaultValue
            case .picker(let key, _, _, let defaultValue):
                strings[key] = defaultValue
            }
        }
    }

    var values: ToolParameterValues {
        var result = ToolParameterValues()
        result.numbers = numbers
        result.strings = strings
        return result
    }
}

struct ToolParameterSheetView: View {
    @ObservedObject var model: ToolParameterSheetModel
    let onApply: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(model.tool.title) — \(model.fileName)")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Form {
                ForEach(Array(model.tool.parameters.enumerated()), id: \.offset) { _, parameter in
                    row(for: parameter)
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Apply", action: onApply)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360, height: 60 + CGFloat(model.tool.parameters.count) * 36 + 40)
    }

    @ViewBuilder
    private func row(for parameter: ToolParameter) -> some View {
        switch parameter {
        case .number(let key, let label, _, let range):
            TextField(label, value: Binding(
                get: { model.numbers[key] ?? 0 },
                set: { model.numbers[key] = min(max($0, range.lowerBound), range.upperBound) }
            ), formatter: Self.numberFormatter)

        case .text(let key, let label, _):
            TextField(label, text: Binding(
                get: { model.strings[key] ?? "" },
                set: { model.strings[key] = $0 }
            ))

        case .picker(let key, let label, let options, _):
            Picker(label, selection: Binding(
                get: { model.strings[key] ?? options.first ?? "" },
                set: { model.strings[key] = $0 }
            )) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
        }
    }

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}

@MainActor
final class ToolParameterWindowController {
    private var window: NSWindow?

    func show(tool: FileTool, fileName: String, onApply: @escaping (ToolParameterValues) -> Void, onCancel: @escaping () -> Void) {
        let model = ToolParameterSheetModel(tool: tool, fileName: fileName)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 60 + CGFloat(tool.parameters.count) * 36 + 40),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = tool.title
        window.isReleasedWhenClosed = false
        window.center()

        let view = ToolParameterSheetView(
            model: model,
            onApply: { [weak self] in
                onApply(model.values)
                self?.close()
            },
            onCancel: { [weak self] in
                onCancel()
                self?.close()
            }
        )
        window.contentView = NSHostingView(rootView: view)
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func close() {
        window?.close()
        window = nil
    }
}
