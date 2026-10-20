import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PDFPagesView: View {
    @ObservedObject var model: PDFPagesModel
    let onSaveAll: () -> Void
    let onExtract: () -> Void
    let onCancel: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 130, maximum: 170), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(model.list.items) { item in
                        PageCell(model: model, item: item)
                    }
                    Color.clear.frame(height: 150)
                        .onDrop(of: [.text], isTargeted: nil) { providers in
                            handleDrop(providers) { model.dropAtEnd($0) }
                        }
                        .accessibilityHidden(true)
                }
                .padding(16)
            }
            Divider()
            footer
        }
        .frame(minWidth: 640, minHeight: 460)
        .alert("Couldn't add that file", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button { model.rotateSelected(by: -90) } label: { Label("Rotate Left", systemImage: "rotate.left") }
                .keyboardShortcut("l", modifiers: .command)
            Button { model.rotateSelected(by: 90) } label: { Label("Rotate Right", systemImage: "rotate.right") }
                .keyboardShortcut("r", modifiers: .command)
            Button { model.moveSelected(by: -1) } label: { Label("Move Earlier", systemImage: "arrow.left") }
                .keyboardShortcut("[", modifiers: .command)
            Button { model.moveSelected(by: 1) } label: { Label("Move Later", systemImage: "arrow.right") }
                .keyboardShortcut("]", modifiers: .command)
            Button(role: .destructive) { model.deleteSelected() } label: { Label("Delete", systemImage: "trash") }
                .keyboardShortcut(.delete, modifiers: [])
            Divider().frame(height: 18)
            Button { addPDF() } label: { Label("Add PDF…", systemImage: "plus.rectangle.on.rectangle") }
                .keyboardShortcut("o", modifiers: .command)
            Button("Select All") { model.selectAll() }
                .keyboardShortcut("a", modifiers: .command)
            Spacer()
        }
        .labelStyle(.titleAndIcon)
        .disabled(false)
        .padding(10)
    }

    private var footer: some View {
        HStack {
            Text("\(model.list.items.count) pages" + (model.selection.isEmpty ? "" : ", \(model.selection.count) selected"))
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Cancel", action: onCancel)
            Button("Extract Selected", action: onExtract)
                .disabled(model.selection.isEmpty)
            Button("Save Copy", action: onSaveAll)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.hasChanges || model.list.items.isEmpty)
        }
        .padding(12)
    }

    private func addPDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.message = "Choose PDFs to add after the last page"
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        Task { for url in urls { await model.addPDF(url) } }
    }
}

private func handleDrop(_ providers: [NSItemProvider], _ action: @escaping (UUID) -> Void) -> Bool {
    guard let provider = providers.first else { return false }
    _ = provider.loadObject(ofClass: NSString.self) { object, _ in
        guard let text = object as? String, let id = UUID(uuidString: text) else { return }
        DispatchQueue.main.async { action(id) }
    }
    return true
}

private struct PageCell: View {
    @ObservedObject var model: PDFPagesModel
    let item: PDFPageItem

    var body: some View {
        let selected = model.selection.contains(item.id)
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor))
                if let image = model.thumbnail(for: item) {
                    Image(nsImage: image).resizable().scaledToFit().padding(6)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(height: 170)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: selected ? 3 : 1))
            Text("\(model.position(of: item.id) ?? 0)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(selected ? Color.accentColor : .secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            let flags = NSEvent.modifierFlags
            model.select(item.id, extend: flags.contains(.command), range: flags.contains(.shift))
        }
        .onAppear { model.requestThumbnail(for: item) }
        .onChange(of: item.rotation) { _ in model.requestThumbnail(for: item) }
        .onDrag { NSItemProvider(object: item.id.uuidString as NSString) }
        .onDrop(of: [.text], isTargeted: nil) { providers in
            handleDrop(providers) { model.drop($0, before: item.id) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(model.position(of: item.id) ?? 0)" + (item.rotation != 0 ? ", rotated \(item.rotation) degrees" : ""))
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.select(item.id, extend: true, range: false) }
    }
}
