import AppKit

/// Runs the six File Actions. Each action reports through the same
/// `JobQueue`/HUD as conversions — "no silent failures" applies here too.
/// Always available for any file, folder, or mixed selection; never
/// consults the Converter registry.
@MainActor
final class FileActionRunner {
    private let jobQueue: JobQueue
    private let floatController: FloatPanelController

    init(jobQueue: JobQueue, floatController: FloatPanelController) {
        self.jobQueue = jobQueue
        self.floatController = floatController
    }

    func perform(_ action: FileAction, on urls: [URL]) {
        guard !urls.isEmpty else { return }
        switch action {
        case .airdrop: airdrop(urls)
        case .float: float(urls)
        case .copy: copyOrMove(urls, move: false)
        case .move: copyOrMove(urls, move: true)
        case .copyPath: copyPath(urls)
        case .terminal: openInTerminal(urls)
        }
    }

    private func airdrop(_ urls: [URL]) {
        let job = Job(displayName: displayName(for: urls), icon: FileAction.airdrop.icon)
        jobQueue.addJob(job) {
            guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else {
                job.state = .failed("AirDrop isn't available for these items.")
                return
            }
            service.perform(withItems: urls)
            job.state = .succeeded(message: "Shared", revealURL: nil)
            self.jobQueue.autoRemoveAfterDelay(job, seconds: 2)
        }
    }

    private func float(_ urls: [URL]) {
        let job = Job(displayName: displayName(for: urls), icon: FileAction.float.icon)
        jobQueue.addJob(job) {
            self.floatController.showFloats(for: urls)
            job.state = .succeeded(message: "Floating", revealURL: nil)
            self.jobQueue.autoRemoveAfterDelay(job, seconds: 2)
        }
    }

    private func copyOrMove(_ urls: [URL], move: Bool) {
        guard let destinationFolder = chooseFolder(prompt: move ? "Move Here" : "Copy Here") else { return }
        let icon = (move ? FileAction.move : FileAction.copy).icon

        for url in urls {
            let job = Job(displayName: url.lastPathComponent, icon: icon)
            jobQueue.addJob(job) {
                do {
                    let destination = try FileActionLogic.copyOrMoveItem(at: url, into: destinationFolder, move: move)
                    job.state = .succeeded(message: move ? "Moved" : "Copied", revealURL: destination)
                    self.jobQueue.autoRemoveAfterDelay(job)
                } catch {
                    job.state = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func copyPath(_ urls: [URL]) {
        let job = Job(displayName: displayName(for: urls), icon: FileAction.copyPath.icon)
        jobQueue.addJob(job) {
            let text = FileActionLogic.pathsText(for: urls)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            job.state = .succeeded(message: urls.count == 1 ? "Path copied" : "\(urls.count) paths copied", revealURL: nil)
            self.jobQueue.autoRemoveAfterDelay(job, seconds: 2)
        }
    }

    private func openInTerminal(_ urls: [URL]) {
        let folders = Set(urls.map(FileActionLogic.folderURL(for:)))
        let job = Job(displayName: displayName(for: urls), icon: FileAction.terminal.icon)
        jobQueue.addJob(job) {
            guard let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
                job.state = .failed("Terminal.app not found.")
                return
            }
            for folder in folders {
                do {
                    _ = try await NSWorkspace.shared.open([folder], withApplicationAt: terminalURL, configuration: NSWorkspace.OpenConfiguration())
                } catch {
                    job.state = .failed(error.localizedDescription)
                    return
                }
            }
            job.state = .succeeded(message: "Opened Terminal", revealURL: nil)
            self.jobQueue.autoRemoveAfterDelay(job, seconds: 2)
        }
    }

    private func chooseFolder(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url
    }

    private func displayName(for urls: [URL]) -> String {
        urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) items"
    }
}
