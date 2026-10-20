import Foundation
import UniformTypeIdentifiers

@MainActor
public final class JobQueue: ObservableObject {
    @Published public private(set) var jobs: [Job] = []

    let settingsStore: SettingsStore
    private var tasks: [UUID: Task<Void, Never>] = [:]

    public init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    public func convert(urls: [URL], to outputType: UTType) {
        for url in urls {
            let job = Job(displayName: url.lastPathComponent, icon: FormatCatalog.icon(for: outputType))
            addJob(job) { [weak self] in
                await self?.runConversion(job, sourceURL: url, outputType: outputType)
            }
        }
    }

    /// Registers `job` and runs `task` for it, tracked for cancellation.
    /// Used by `convert` above and by `FileActionRunner` for Copy/Move/etc.
    func addJob(_ job: Job, task: @escaping () async -> Void) {
        jobs.append(job)
        tasks[job.id] = Task { await task() }
    }

    /// Shows a failure in the HUD for something that never became a running job
    /// (e.g. an editor that couldn't open its file).
    public func reportFailure(displayName: String, icon: String = "exclamationmark.triangle", message: String) {
        let job = Job(displayName: displayName, icon: icon)
        job.state = .failed(message)
        addJob(job) {}
    }

    public func cancel(_ job: Job) {
        tasks[job.id]?.cancel()
    }

    /// Drops a finished job from the list (called by the HUD's dismiss
    /// button, and automatically a few seconds after success).
    func remove(_ job: Job) {
        jobs.removeAll { $0.id == job.id }
        tasks[job.id] = nil
    }

    func autoRemoveAfterDelay(_ job: Job, seconds: Double = 4) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            self?.remove(job)
        }
    }

    private func runConversion(_ job: Job, sourceURL: URL, outputType: UTType) async {
        let inputType = (try? sourceURL.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: sourceURL.pathExtension)

        guard let inputType, let converter = ConverterRegistry.shared.converter(from: inputType, to: outputType) else {
            job.state = .failed(ConversionError.noConverterAvailable.localizedDescription)
            tasks[job.id] = nil
            return
        }

        let destinationFolder = settingsStore.customOutputFolderPath.map(URL.init(fileURLWithPath:))
            ?? sourceURL.deletingLastPathComponent()
        let outputURL = OutputPathPlanner.nonClobberingURL(for: sourceURL, outputType: outputType, in: destinationFolder)

        do {
            let result = try await converter.convert(input: sourceURL, output: outputURL, options: ConversionOptions()) { progress in
                Task { @MainActor in job.progress = progress }
            }
            try Task.checkCancellation()
            job.state = .succeeded(message: result.warning ?? "Done", revealURL: result.outputURL)
            autoRemoveAfterDelay(job)
        } catch is CancellationError {
            job.state = .cancelled
        } catch {
            job.state = .failed(error.localizedDescription)
        }
        tasks[job.id] = nil
    }
}
