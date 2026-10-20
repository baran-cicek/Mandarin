import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Executes the 26 File Tools. Every tool but the three Merge ones works
/// on each dropped item independently (one `Job` each, same convention as
/// Convert/File Actions); Merge combines the whole selection into one
/// output, one `Job` for the batch. All built on frameworks/tools already
/// integrated and tested in Milestones 3-6 (ImageIO, PDFKit, ffmpeg,
/// system zip) — no new external dependency.
@MainActor
public final class FileToolRunner {
    private let jobQueue: JobQueue

    public init(jobQueue: JobQueue) {
        self.jobQueue = jobQueue
    }

    public func perform(_ tool: FileTool, on urls: [URL], parameters: ToolParameterValues) {
        guard !urls.isEmpty else { return }

        if tool.requiresMultipleFiles {
            runMerge(tool, urls: urls)
            return
        }

        for url in urls {
            let job = Job(displayName: url.lastPathComponent, icon: tool.icon)
            jobQueue.addJob(job) { [weak self] in
                await self?.run(tool, on: url, parameters: parameters, job: job)
            }
        }
    }

    private func destinationFolder(for url: URL) -> URL {
        jobQueue.settingsStore.customOutputFolderPath.map(URL.init(fileURLWithPath:)) ?? url.deletingLastPathComponent()
    }

    private func run(_ tool: FileTool, on url: URL, parameters: ToolParameterValues, job: Job) async {
        do {
            let inputType = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
                ?? UTType(filenameExtension: url.pathExtension) ?? .data
            let folder = destinationFolder(for: url)
            let result: ConversionResult

            switch tool.category {
            case .image:
                let output = OutputPathPlanner.nonClobberingURL(for: url, outputType: inputType, in: folder)
                result = try runImageTool(tool, input: url, output: output, parameters: parameters)
            case .video, .audio:
                let output = OutputPathPlanner.nonClobberingURL(for: url, outputType: inputType, in: folder)
                result = try await runMediaTool(tool, input: url, output: output, parameters: parameters) { progress in
                    Task { @MainActor in job.progress = progress }
                }
            case .pdf:
                result = try runPDFTool(tool, input: url, folder: folder, parameters: parameters)
            case .archive:
                let output = OutputPathPlanner.nonClobberingURL(copying: url, into: folder).appendingPathExtension("zip")
                result = try await runArchiveCompress(input: url, output: output)
            }

            try Task.checkCancellation()
            job.state = .succeeded(message: result.warning ?? "Done", revealURL: result.outputURL)
            jobQueue.autoRemoveAfterDelay(job)
        } catch is CancellationError {
            job.state = .cancelled
        } catch {
            job.state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Image

    private func runImageTool(_ tool: FileTool, input: URL, output: URL, parameters: ToolParameterValues) throws -> ConversionResult {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ConversionError.cannotReadInput
        }
        let inputType = (try? input.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? .png

        let processed: CGImage
        var quality = 0.9
        switch tool {
        case .compressImage:
            processed = image
            quality = parameters.number("quality")
        case .resizeImage:
            processed = try FileToolImaging.resize(image, width: Int(parameters.number("width")), height: Int(parameters.number("height")))
        case .cropImage:
            processed = try FileToolImaging.crop(
                image,
                x: Int(parameters.number("x")), y: Int(parameters.number("y")),
                width: Int(parameters.number("width")), height: Int(parameters.number("height"))
            )
        case .rotateImage:
            processed = try FileToolImaging.rotate(image, degrees: parameters.number("degrees"))
        case .flipImage:
            processed = try FileToolImaging.flip(image, horizontal: parameters.string("axis") != "Vertical")
        case .grayscaleImage:
            processed = try FileToolImaging.grayscale(image)
        case .stripMetadataImage:
            processed = image // re-encoding without copying source properties already drops metadata
        default:
            throw ConversionError.unsupportedRoute("\(tool.title) isn't an image tool.")
        }

        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, inputType.identifier as CFString, 1, nil) else {
            throw ConversionError.cannotWriteOutput
        }
        CGImageDestinationAddImage(destination, processed, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ConversionError.cannotWriteOutput
        }
        return ConversionResult(outputURL: output)
    }

    // MARK: - Video / Audio (ffmpeg)

    private func runMediaTool(_ tool: FileTool, input: URL, output: URL, parameters: ToolParameterValues, progress: @escaping (Double) -> Void) async throws -> ConversionResult {
        guard let ffmpegPath = ExternalTool.ffmpeg.path else {
            throw ConversionError.missingTool(name: ExternalTool.ffmpeg.name, installHint: ExternalTool.ffmpeg.installHint)
        }
        var args = ["-y", "-i", input.path]
        let warning: String? = nil

        switch tool {
        case .compressVideo:
            args += ["-c:v", "libx264", "-crf", "30", "-c:a", "aac", "-b:a", "96k"]
        case .resizeVideo:
            args += ["-vf", "scale=\(Int(parameters.number("width"))):\(Int(parameters.number("height")))"]
        case .cropVideo:
            args += ["-vf", "crop=\(Int(parameters.number("width"))):\(Int(parameters.number("height"))):\(Int(parameters.number("x"))):\(Int(parameters.number("y")))"]
        case .trimVideo, .trimAudio:
            let start = parameters.number("start")
            let end = parameters.number("end")
            guard end > start else { throw ConversionError.toolFailed("End must be after start.") }
            args += ["-ss", String(start), "-to", String(end)]
        case .rotateVideo:
            args += FileToolMediaArgs.rotationFilter(degrees: parameters.number("degrees"))
        case .changeSpeedVideo:
            let speed = parameters.number("speed")
            args += ["-filter_complex", "[0:v]setpts=PTS/\(speed)[v];[0:a]atempo=\(speed)[a]", "-map", "[v]", "-map", "[a]"]
        case .changeSpeedAudio:
            let speed = parameters.number("speed")
            args += ["-filter:a", "atempo=\(speed)"]
        case .extractAudio:
            args += ["-vn"]
        case .grayscaleVideo:
            args += ["-vf", "hue=s=0"]
        default:
            throw ConversionError.unsupportedRoute("\(tool.title) isn't a media tool.")
        }

        let finalOutput: URL
        if tool == .extractAudio {
            finalOutput = Self.renamedExtension(output, to: "mp3")
        } else {
            finalOutput = output
        }
        args += ["-progress", "pipe:1", "-loglevel", "error", finalOutput.path]

        let totalDuration = FileToolMediaArgs.probeDuration(of: input)
        try await FFmpegRunner.run(ffmpegPath: ffmpegPath, arguments: args, totalDuration: totalDuration, output: finalOutput, progress: progress)
        return ConversionResult(outputURL: finalOutput, warning: warning)
    }

    private static func renamedExtension(_ url: URL, to newExtension: String) -> URL {
        let folder = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        var candidate = folder.appendingPathComponent(base).appendingPathExtension(newExtension)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(counter)").appendingPathExtension(newExtension)
            counter += 1
        }
        return candidate
    }

    // MARK: - PDF

    private func runPDFTool(_ tool: FileTool, input: URL, folder: URL, parameters: ToolParameterValues) throws -> ConversionResult {
        guard let document = PDFDocument(url: input) else {
            throw ConversionError.cannotReadInput
        }

        switch tool {
        case .compressPDF:
            let output = OutputPathPlanner.nonClobberingURL(for: input, outputType: .pdf, in: folder)
            try FileToolPDF.compress(document, to: output)
            return ConversionResult(outputURL: output, warning: "Best effort — pages are rasterized, text is no longer selectable")

        case .rotatePDF:
            let output = OutputPathPlanner.nonClobberingURL(for: input, outputType: .pdf, in: folder)
            let degrees = Int(parameters.number("degrees"))
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                page.rotation = (page.rotation + degrees).normalizedRotation
            }
            guard document.write(to: output) else { throw ConversionError.cannotWriteOutput }
            return ConversionResult(outputURL: output)

        case .stripMetadataPDF:
            let output = OutputPathPlanner.nonClobberingURL(for: input, outputType: .pdf, in: folder)
            document.documentAttributes = [:]
            guard document.write(to: output) else { throw ConversionError.cannotWriteOutput }
            return ConversionResult(outputURL: output)

        case .extractPagesPDF:
            let output = OutputPathPlanner.nonClobberingURL(for: input, outputType: .pdf, in: folder)
            let pageNumbers = FileToolPDF.parsePageRange(parameters.string("pages"), pageCount: document.pageCount)
            guard !pageNumbers.isEmpty else { throw ConversionError.toolFailed("No valid pages in range.") }
            let newDocument = PDFDocument()
            for (index, pageNumber) in pageNumbers.enumerated() {
                guard let page = document.page(at: pageNumber - 1) else { continue }
                newDocument.insert(page, at: index)
            }
            guard newDocument.write(to: output) else { throw ConversionError.cannotWriteOutput }
            return ConversionResult(outputURL: output)

        case .splitPDF:
            guard document.pageCount > 1 else {
                throw ConversionError.toolFailed("This PDF only has one page — nothing to split.")
            }
            let baseName = input.deletingPathExtension().lastPathComponent
            let outputFolder = OutputPathPlanner.nonClobberingFolder(named: baseName, in: folder)
            try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
            let digits = String(document.pageCount).count
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                let single = PDFDocument()
                single.insert(page, at: 0)
                let pageNumber = String(format: "%0\(digits)d", index + 1)
                let pageURL = outputFolder.appendingPathComponent("\(baseName)-\(pageNumber)").appendingPathExtension("pdf")
                guard single.write(to: pageURL) else { throw ConversionError.cannotWriteOutput }
            }
            return ConversionResult(outputURL: outputFolder)

        default:
            throw ConversionError.unsupportedRoute("\(tool.title) isn't a single-file PDF tool.")
        }
    }

    // MARK: - Archive

    private func runArchiveCompress(input: URL, output: URL) async throws -> ConversionResult {
        try await ProcessRunner.run("/usr/bin/zip", arguments: ["-r", "-q", output.path, input.lastPathComponent], currentDirectory: input.deletingLastPathComponent())
        return ConversionResult(outputURL: output)
    }

    // MARK: - Merge (video/audio/PDF — one job for the whole selection)

    private func runMerge(_ tool: FileTool, urls: [URL]) {
        let folder = destinationFolder(for: urls[0])
        let job = Job(displayName: "\(urls.count) items", icon: tool.icon)
        jobQueue.addJob(job) { [weak self] in
            guard let self else { return }
            do {
                let result: ConversionResult
                switch tool {
                case .mergePDF:
                    result = try self.mergePDFs(urls, folder: folder)
                case .mergeVideo:
                    result = try await self.mergeMedia(urls, folder: folder, extension: "mp4", hasVideo: true)
                case .mergeAudio:
                    result = try await self.mergeMedia(urls, folder: folder, extension: "m4a", hasVideo: false)
                default:
                    throw ConversionError.unsupportedRoute("\(tool.title) isn't a merge tool.")
                }
                try Task.checkCancellation()
                job.state = .succeeded(message: result.warning ?? "Done", revealURL: result.outputURL)
                self.jobQueue.autoRemoveAfterDelay(job)
            } catch is CancellationError {
                job.state = .cancelled
            } catch {
                job.state = .failed(error.localizedDescription)
            }
        }
    }

    private func mergePDFs(_ urls: [URL], folder: URL) throws -> ConversionResult {
        let merged = PDFDocument()
        var pageIndex = 0
        for url in urls {
            guard let document = PDFDocument(url: url) else {
                throw ConversionError.toolFailed("Couldn't read \(url.lastPathComponent) as a PDF.")
            }
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                merged.insert(page, at: pageIndex)
                pageIndex += 1
            }
        }
        let output = OutputPathPlanner.nonClobberingURL(for: URL(fileURLWithPath: "Merged.pdf"), outputType: .pdf, in: folder)
        guard merged.write(to: output) else { throw ConversionError.cannotWriteOutput }
        return ConversionResult(outputURL: output)
    }

    private func mergeMedia(_ urls: [URL], folder: URL, extension outputExtension: String, hasVideo: Bool) async throws -> ConversionResult {
        guard let ffmpegPath = ExternalTool.ffmpeg.path else {
            throw ConversionError.missingTool(name: ExternalTool.ffmpeg.name, installHint: ExternalTool.ffmpeg.installHint)
        }
        let output = OutputPathPlanner.nonClobberingURL(for: URL(fileURLWithPath: "Merged.\(outputExtension)"), outputType: UTType(filenameExtension: outputExtension) ?? .data, in: folder)

        var args = ["-y"]
        for url in urls { args += ["-i", url.path] }

        // e.g. for 2 inputs with video: "[0:v][0:a][1:v][1:a]concat=n=2:v=1:a=1[outv][outa]"
        let streamRefs = urls.indices.map { hasVideo ? "[\($0):v][\($0):a]" : "[\($0):a]" }.joined()
        if hasVideo {
            args += ["-filter_complex", "\(streamRefs)concat=n=\(urls.count):v=1:a=1[outv][outa]", "-map", "[outv]", "-map", "[outa]"]
        } else {
            args += ["-filter_complex", "\(streamRefs)concat=n=\(urls.count):v=0:a=1[outa]", "-map", "[outa]"]
        }
        args += ["-loglevel", "error", output.path]

        try await ProcessRunner.run(ffmpegPath, arguments: args)
        return ConversionResult(outputURL: output)
    }
}

private extension Int {
    /// Normalizes a PDF page rotation to one of 0/90/180/270.
    var normalizedRotation: Int {
        ((self % 360) + 360) % 360
    }
}
