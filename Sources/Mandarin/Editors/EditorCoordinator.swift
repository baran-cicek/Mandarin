import AppKit
import SwiftUI

/// Decides whether a File Tool opens a visual editor (instead of the numeric
/// sheet), loads what the editor needs off the main thread, and opens it.
@MainActor
public final class EditorCoordinator {
    private let windows = EditorWindowManager()
    private let exporter: EditorExporter
    private let settingsStore: SettingsStore
    private let reportError: (String, String) -> Void

    /// `reportError(fileName, message)` surfaces a failure in the HUD.
    public init(jobQueue: JobQueue, settingsStore: SettingsStore, showHUD: @escaping () -> Void,
                reportError: @escaping (String, String) -> Void) {
        self.exporter = EditorExporter(jobQueue: jobQueue, showHUD: showHUD)
        self.settingsStore = settingsStore
        self.reportError = reportError
    }

    /// True when an editor handles this tool/selection (the caller then skips the sheet).
    public func open(_ tool: FileTool, urls: [URL]) -> Bool {
        guard let kind = EditorKind.kind(for: tool, selectionCount: urls.count), let url = urls.first else { return false }
        let folder = settingsStore.customOutputFolderPath.map(URL.init(fileURLWithPath:)) ?? url.deletingLastPathComponent()
        let exporter = self.exporter
        let windows = self.windows
        Task { [weak self] in
            do {
                switch kind {
                case .photo:
                    let model = try await PhotoEditorModel.load(url)
                    windows.open(key: "photo:" + url.path, title: "Edit Photo — \(url.lastPathComponent)", size: NSSize(width: 1020, height: 680)) { close in
                        PhotoEditorView(model: model, onSave: {
                            let edits = model.exportEdits
                            exporter.export(displayName: url.lastPathComponent, icon: "photo") { _ in
                                try PhotoPipeline.export(source: url, edits: edits, folder: folder)
                            }
                            close()
                        }, onCancel: close)
                    }
                case .pdfPages:
                    let model = try await PDFPagesModel.load(url)
                    windows.open(key: "pdf:" + url.path, title: "PDF Pages — \(url.lastPathComponent)", size: NSSize(width: 860, height: 640)) { close in
                        PDFPagesView(model: model, onSaveAll: {
                            let items = model.list.items, sources = model.sources
                            let output = EditorNaming.outputURL(for: url, in: folder)
                            exporter.export(displayName: url.lastPathComponent, icon: "doc.on.doc") { _ in
                                try PDFPageBuilder.export(items, sources: sources, to: output)
                            }
                            close()
                        }, onExtract: {
                            let items = model.list.subset(model.selection), sources = model.sources
                            let output = EditorNaming.outputURL(for: url, suffix: "pages", in: folder)
                            exporter.export(displayName: url.lastPathComponent, icon: "doc.on.doc") { _ in
                                try PDFPageBuilder.export(items, sources: sources, to: output)
                            }
                            close()
                        }, onCancel: close)
                    }
                case .background:
                    let model = try await BackgroundEditorModel.load(url)
                    windows.open(key: "background:" + url.path, title: "Background — \(url.lastPathComponent)", size: NSSize(width: 960, height: 640)) { close in
                        BackgroundEditorView(model: model, onSave: {
                            let edit = model.edit
                            exporter.export(displayName: url.lastPathComponent, icon: "photo.on.rectangle") { _ in
                                try BackgroundTool.export(source: url, edit: edit, folder: folder)
                            }
                            close()
                        }, onCancel: close)
                    }
                case .audio:
                    let model = try await AudioEditorModel.load(url)
                    windows.open(key: "audio:" + url.path, title: "Trim Audio — \(url.lastPathComponent)", size: NSSize(width: 760, height: 500), onClose: { model.cancelWork() }) { close in
                        AudioEditorView(model: model, onSave: {
                            let plan = model.plan
                            let output = EditorNaming.outputURL(for: url, suffix: "trimmed", in: folder)
                            exporter.export(displayName: url.lastPathComponent, icon: "scissors") { progress in
                                try await AudioExport.export(source: url, plan: plan, output: output, progress: progress)
                            }
                            close()
                        }, onSplit: {
                            guard let (first, second) = model.plan.split(at: model.player.playhead) else { return }
                            for (index, plan) in [first, second].enumerated() {
                                let output = EditorNaming.outputURL(for: url, suffix: "part \(index + 1)", in: folder)
                                exporter.export(displayName: url.lastPathComponent, icon: "scissors") { progress in
                                    try await AudioExport.export(source: url, plan: plan, output: output, progress: progress)
                                }
                            }
                            close()
                        }, onCancel: close)
                    }
                case .video:
                    let model = try await VideoEditorModel.load(url)
                    windows.open(key: "video:" + url.path, title: "Trim Video — \(url.lastPathComponent)", size: NSSize(width: 860, height: 760), onClose: { model.cancelWork() }) { close in
                        VideoEditorView(model: model, onSave: {
                            let plan = model.plan
                            let output = EditorNaming.outputURL(for: url, suffix: "trimmed", in: folder)
                            exporter.export(displayName: url.lastPathComponent, icon: "scissors") { progress in
                                try await VideoExport.export(source: url, plan: plan, output: output, progress: progress)
                            }
                            close()
                        }, onCancel: close)
                    }
                }
            } catch {
                self?.reportError(url.lastPathComponent, error.localizedDescription)
            }
        }
        return true
    }
}
