// Headless CLI for scripted end-to-end verification: drives the exact
// same ConverterRegistry/JobQueue a real Convert-wheel drop uses, on a
// given file and target extension, printing progress and the final
// result. Doesn't change app behavior — purely additive, built on the
// public surface Milestone 3-5 already exposed for MandarinSelfTests.
//
// Usage:
//   MandarinConvert <inputPath> <outputExtension> [--output-dir DIR] [--cancel-after SECONDS]
//
// Prints "PROGRESS 0.00"-"PROGRESS 1.00" lines while running, then one of:
//   RESULT succeeded message="..." path=/abs/path/to/output
//   RESULT failed message="..."
//   RESULT cancelled
// Exit code 0 for succeeded/cancelled, 1 for failed or bad arguments.

import Foundation
import Mandarin
import UniformTypeIdentifiers

@MainActor
func run() async {
    let arguments = CommandLine.arguments

    if arguments.count >= 3, arguments[1] == "--list-targets" {
        let url = URL(fileURLWithPath: arguments[2])
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: url.pathExtension) ?? .data
        let targets = ConverterRegistry.shared.availableTargets(for: type)
        print("input type: \(type.identifier)")
        print("target count: \(targets.count)")
        for target in targets {
            print("  - \(target.identifier) (.\(FormatCatalog.fileExtension(for: target)))")
        }
        exit(0)
    }

    guard arguments.count >= 3 else {
        FileHandle.standardError.write(Data("Usage: MandarinConvert <inputPath> <outputExtension> [--output-dir DIR] [--cancel-after SECONDS]\n".utf8))
        exit(1)
    }

    let inputURL = URL(fileURLWithPath: arguments[1])
    let outputExtension = arguments[2]
    var outputDir: String?
    var cancelAfter: Double?

    var index = 3
    while index < arguments.count {
        switch arguments[index] {
        case "--output-dir":
            index += 1
            outputDir = arguments[index]
        case "--cancel-after":
            index += 1
            cancelAfter = Double(arguments[index])
        default:
            break
        }
        index += 1
    }

    guard let outputType = UTType(filenameExtension: outputExtension) else {
        print("RESULT failed message=\"unknown output extension .\(outputExtension)\"")
        exit(1)
    }

    let settingsStore = SettingsStore()
    if let outputDir {
        settingsStore.customOutputFolderPath = outputDir
    }
    let jobQueue = JobQueue(settingsStore: settingsStore)

    jobQueue.convert(urls: [inputURL], to: outputType)
    guard let job = jobQueue.jobs.last else {
        print("RESULT failed message=\"job was not created\"")
        exit(1)
    }

    if let cancelAfter {
        Task {
            try? await Task.sleep(for: .seconds(cancelAfter))
            jobQueue.cancel(job)
        }
    }

    var lastPrinted = -1.0
    while true {
        switch job.state {
        case .running:
            if job.progress - lastPrinted >= 0.05 || lastPrinted < 0 {
                print("PROGRESS \(String(format: "%.2f", job.progress))")
                lastPrinted = job.progress
            }
            try? await Task.sleep(for: .milliseconds(100))
        case .succeeded(let message, let revealURL):
            print("RESULT succeeded message=\"\(message)\" path=\(revealURL?.path ?? "")")
            exit(0)
        case .failed(let message):
            print("RESULT failed message=\"\(message)\"")
            exit(1)
        case .cancelled:
            print("RESULT cancelled")
            exit(0)
        }
    }
}

await run()
