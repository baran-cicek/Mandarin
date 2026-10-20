// Lightweight, framework-free test runner.
//
// This machine has only Xcode Command Line Tools installed, no full
// Xcode.app. Both XCTest (framework itself is missing from CLT) and Swift
// Testing (its macro plugin is Xcode-only, same root cause as the `@State`
// issue in the main app — see PROGRESS.md) fail to build here. So instead
// of a `.testTarget`, this is a second plain executable target that
// `import`s Mandarin and asserts directly, printing PASS/FAIL and exiting
// non-zero on any failure. Run it with `swift run MandarinSelfTests`.

import AppKit
import AVFoundation
import Foundation
import ImageIO
import Mandarin
import PDFKit
import UniformTypeIdentifiers

struct TestFailure: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

var totalCount = 0
var failureCount = 0

@MainActor
func check(_ name: String, _ condition: @autoclosure () -> Bool) {
    totalCount += 1
    if condition() {
        print("  ok   - \(name)")
    } else {
        failureCount += 1
        print("  FAIL - \(name)")
    }
}

func skip(_ name: String, because reason: String) {
    print("  skip - \(name) (\(reason))")
}

@MainActor
func run(_ name: String, _ body: () async throws -> Void) async {
    totalCount += 1
    do {
        try await body()
        print("  ok   - \(name)")
    } catch {
        failureCount += 1
        print("  FAIL - \(name): \(error)")
    }
}

func makeTestCGImage(width: Int = 20, height: Int = 20) -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

func writeTestImage(type: UTType, width: Int = 20, height: Int = 20) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension(type.preferredFilenameExtension ?? "png")
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
        throw TestFailure("couldn't create image destination")
    }
    CGImageDestinationAddImage(destination, makeTestCGImage(width: width, height: height), nil)
    guard CGImageDestinationFinalize(destination) else {
        throw TestFailure("couldn't finalize test fixture image")
    }
    return url
}

/// Generates a short synthetic MP4 (video + audio) with ffmpeg's `lavfi`
/// test sources — no bundled sample media needed.
func makeTestVideo(seconds: Double = 1, size: String = "320x240") throws -> URL {
    guard let ffmpegPath = ExternalTool.ffmpeg.path else { throw TestFailure("ffmpeg not available") }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: ffmpegPath)
    process.standardInput = FileHandle.nullDevice
    process.arguments = [
        "-nostdin", "-y", "-f", "lavfi", "-i", "testsrc=duration=\(seconds):size=\(size):rate=30",
        "-f", "lavfi", "-i", "sine=frequency=440:duration=\(seconds)",
        "-shortest", "-c:v", "libx264", "-c:a", "aac", "-loglevel", "error", url.path,
    ]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: url.path) else {
        throw TestFailure("failed to generate the synthetic test video")
    }
    return url
}

/// Polls a `Job` until it's done (or times out after 30s) — used by
/// FileToolRunner tests, which drive a real `JobQueue` the same way a real
/// drop does, rather than calling tool logic directly.
@MainActor
func waitForJob(_ job: Job, timeoutSeconds: Double = 30) async throws {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while case .running = job.state {
        if Date() > deadline { throw TestFailure("job timed out after \(timeoutSeconds)s") }
        try await Task.sleep(for: .milliseconds(50))
    }
}

/// A small real PDF with actual extractable text — built natively via
/// CoreGraphics + `NSAttributedString` drawing, no external tool needed.
func makeTestPDF(pageCount: Int = 1, text: String = "Mandarin test PDF content", pageWidth: CGFloat = 200) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("pdf")
    var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: 200)
    let pdfData = NSMutableData()
    guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
          let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        throw TestFailure("couldn't create a PDF context")
    }

    for pageIndex in 0..<pageCount {
        context.beginPage(mediaBox: &mediaBox)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(mediaBox)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let attributedString = NSAttributedString(
            string: "\(text) (page \(pageIndex + 1))",
            attributes: [.font: NSFont.systemFont(ofSize: 14)]
        )
        attributedString.draw(at: CGPoint(x: 10, y: 170))
        NSGraphicsContext.restoreGraphicsState()

        context.endPage()
    }
    context.closePDF()
    try pdfData.write(to: url, options: .atomic)
    return url
}

print("Mandarin self-tests\n")

print("ImageConverter")

await run("JPG to PNG preserves pixel dimensions") {
    let input = try writeTestImage(type: .jpeg, width: 32, height: 24)
    defer { try? FileManager.default.removeItem(at: input) }
    let output = input.deletingPathExtension().appendingPathExtension("png")
    defer { try? FileManager.default.removeItem(at: output) }

    _ = try await ImageConverter().convert(input: input, output: output, options: ConversionOptions()) { _ in }

    guard FileManager.default.fileExists(atPath: output.path) else { throw TestFailure("output file missing") }
    let source = CGImageSourceCreateWithURL(output as CFURL, nil)!
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    guard image.width == 32, image.height == 24 else {
        throw TestFailure("expected 32x24, got \(image.width)x\(image.height)")
    }
}

await run("PNG to PDF produces a readable PDF") {
    let input = try writeTestImage(type: .png)
    defer { try? FileManager.default.removeItem(at: input) }
    let output = input.deletingPathExtension().appendingPathExtension("pdf")
    defer { try? FileManager.default.removeItem(at: output) }

    _ = try await ImageConverter().convert(input: input, output: output, options: ConversionOptions()) { _ in }

    let data = try Data(contentsOf: output)
    guard data.starts(with: Data("%PDF".utf8)) else { throw TestFailure("output isn't a PDF") }
}

if ExternalTool.cwebp.isAvailable {
    await run("PNG to WebP produces a valid WebP (via cwebp)") {
        let input = try writeTestImage(type: .png, width: 16, height: 16)
        defer { try? FileManager.default.removeItem(at: input) }
        let output = input.deletingPathExtension().appendingPathExtension("webp")
        defer { try? FileManager.default.removeItem(at: output) }

        _ = try await ImageConverter().convert(input: input, output: output, options: ConversionOptions()) { _ in }

        let data = try Data(contentsOf: output)
        guard data.count > 12,
              data[0..<4] == Data("RIFF".utf8),
              data[8..<12] == Data("WEBP".utf8) else {
            throw TestFailure("output isn't a WebP container")
        }
    }
} else {
    skip("PNG to WebP produces a valid WebP (via cwebp)", because: "cwebp not installed")
}

await run("SVG input rasterizes at 4x the declared size") {
    let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10" fill="red"/></svg>"#
    let input = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString).appendingPathExtension("svg")
    try svg.write(to: input, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: input) }
    let output = input.deletingPathExtension().appendingPathExtension("png")
    defer { try? FileManager.default.removeItem(at: output) }

    _ = try await ImageConverter().convert(input: input, output: output, options: ConversionOptions()) { _ in }

    let source = CGImageSourceCreateWithURL(output as CFURL, nil)!
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    guard image.width == 40, image.height == 40 else {
        throw TestFailure("expected 40x40, got \(image.width)x\(image.height)")
    }
}

do {
    let converter = ImageConverter()
    check("canConvert allows JPEG to PDF", converter.canConvert(from: .jpeg, to: .pdf))
    check("canConvert rejects SVG as an output", !converter.canConvert(from: .jpeg, to: .svg))
    check("canConvert rejects PDF as an input", !converter.canConvert(from: .pdf, to: .jpeg))
}

print("\nConverterRegistry")

do {
    let targets = ConverterRegistry.shared.availableTargets(for: .jpeg)
    check("JPEG targets exclude JPEG itself", !targets.contains(.jpeg))
    check("JPEG targets include PNG", targets.contains(.png))

    // .docx used to be the "nothing can touch this" example here, back when
    // only images were supported — now it has real Document targets (see
    // below), so this needs a type that's *deliberately* never supported:
    // PAGES, since no available tool can write Apple's proprietary iWork
    // format (see DocumentFormats.swift).
    let pages = UTType(filenameExtension: "pages")!
    check("Unsupported type (PAGES) has no targets", ConverterRegistry.shared.availableTargets(for: pages).isEmpty)
}

print("\nOutputPathPlanner")

await run("Non-clobbering names increment as 'name 2', 'name 3', ...") {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let source = dir.appendingPathComponent("photo.heic")
    let first = OutputPathPlanner.nonClobberingURL(for: source, outputType: .png, in: dir)
    guard first.lastPathComponent == "photo.png" else { throw TestFailure("expected photo.png, got \(first.lastPathComponent)") }
    FileManager.default.createFile(atPath: first.path, contents: Data())

    let second = OutputPathPlanner.nonClobberingURL(for: source, outputType: .png, in: dir)
    guard second.lastPathComponent == "photo 2.png" else { throw TestFailure("expected 'photo 2.png', got \(second.lastPathComponent)") }
}

await run("Non-clobbering copy/move names keep the original extension") {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let source = dir.appendingPathComponent("report.pdf")
    let first = OutputPathPlanner.nonClobberingURL(copying: source, into: dir)
    guard first.lastPathComponent == "report.pdf" else { throw TestFailure("expected report.pdf, got \(first.lastPathComponent)") }
    FileManager.default.createFile(atPath: first.path, contents: Data())

    let second = OutputPathPlanner.nonClobberingURL(copying: source, into: dir)
    guard second.lastPathComponent == "report 2.pdf" else { throw TestFailure("expected 'report 2.pdf', got \(second.lastPathComponent)") }
}

await run("Non-clobbering copy/move names handle extensionless files and folders") {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let source = dir.appendingPathComponent("Project")
    let first = OutputPathPlanner.nonClobberingURL(copying: source, into: dir)
    guard first.lastPathComponent == "Project" else { throw TestFailure("expected 'Project', got \(first.lastPathComponent)") }
    try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)

    let second = OutputPathPlanner.nonClobberingURL(copying: source, into: dir)
    guard second.lastPathComponent == "Project 2" else { throw TestFailure("expected 'Project 2', got \(second.lastPathComponent)") }
}

print("\nFileActionLogic (Copy, Move, Copy Path, Terminal)")

await run("Copy keeps the original and creates a non-clobbering copy") {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let source = dir.appendingPathComponent("note.txt")
    try "hello".write(to: source, atomically: true, encoding: .utf8)
    let destFolder = dir.appendingPathComponent("dest")
    try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)

    let copy1 = try FileActionLogic.copyOrMoveItem(at: source, into: destFolder, move: false)
    guard copy1.lastPathComponent == "note.txt" else { throw TestFailure("expected note.txt, got \(copy1.lastPathComponent)") }
    guard FileManager.default.fileExists(atPath: source.path) else { throw TestFailure("original should still exist after copy") }

    let copy2 = try FileActionLogic.copyOrMoveItem(at: source, into: destFolder, move: false)
    guard copy2.lastPathComponent == "note 2.txt" else { throw TestFailure("expected 'note 2.txt', got \(copy2.lastPathComponent)") }
    guard FileManager.default.fileExists(atPath: source.path) else { throw TestFailure("original should still exist after second copy") }
}

await run("Move removes the original and lands at a non-clobbering name") {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let source = dir.appendingPathComponent("draft.txt")
    try "draft".write(to: source, atomically: true, encoding: .utf8)
    let destFolder = dir.appendingPathComponent("dest")
    try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)

    let moved = try FileActionLogic.copyOrMoveItem(at: source, into: destFolder, move: true)
    guard moved.lastPathComponent == "draft.txt" else { throw TestFailure("expected draft.txt, got \(moved.lastPathComponent)") }
    guard !FileManager.default.fileExists(atPath: source.path) else { throw TestFailure("original should be gone after move") }
    guard FileManager.default.fileExists(atPath: moved.path) else { throw TestFailure("moved file should exist at destination") }
}

await run("Moving into a folder that already has the same name doesn't overwrite it") {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let destFolder = dir.appendingPathComponent("dest")
    try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)

    // Something already named "draft.txt" is sitting in the destination —
    // not created by our own planner, just already there.
    let existing = destFolder.appendingPathComponent("draft.txt")
    try "existing content — must survive".write(to: existing, atomically: true, encoding: .utf8)

    let source = dir.appendingPathComponent("draft.txt")
    try "new content".write(to: source, atomically: true, encoding: .utf8)

    let moved = try FileActionLogic.copyOrMoveItem(at: source, into: destFolder, move: true)
    guard moved.lastPathComponent == "draft 2.txt" else { throw TestFailure("expected 'draft 2.txt', got \(moved.lastPathComponent)") }
    let existingContent = try String(contentsOf: existing, encoding: .utf8)
    guard existingContent == "existing content — must survive" else { throw TestFailure("pre-existing file was overwritten") }
}

await run("Copy/Move into a missing destination folder fails clearly, doesn't crash") {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let source = dir.appendingPathComponent("note.txt")
    try "hello".write(to: source, atomically: true, encoding: .utf8)
    let missingFolder = dir.appendingPathComponent("does-not-exist")

    var didThrow = false
    do {
        _ = try FileActionLogic.copyOrMoveItem(at: source, into: missingFolder, move: false)
    } catch {
        didThrow = true
    }
    guard didThrow else { throw TestFailure("expected an error for a missing destination folder") }
}

await run("Copy/Move into a read-only destination folder fails clearly, doesn't crash") {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let source = dir.appendingPathComponent("note.txt")
    try "hello".write(to: source, atomically: true, encoding: .utf8)

    let readOnlyFolder = dir.appendingPathComponent("locked")
    try FileManager.default.createDirectory(at: readOnlyFolder, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: readOnlyFolder.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: readOnlyFolder.path) }

    var didThrow = false
    do {
        _ = try FileActionLogic.copyOrMoveItem(at: source, into: readOnlyFolder, move: false)
    } catch {
        didThrow = true
    }
    guard didThrow else { throw TestFailure("expected an error for a read-only destination folder") }
}

check("Copy Path formats a single path with no trailing newline",
      FileActionLogic.pathsText(for: [URL(fileURLWithPath: "/tmp/a.txt")]) == "/tmp/a.txt")

check("Copy Path joins several paths with one newline each",
      FileActionLogic.pathsText(for: [URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b.txt")])
        == "/tmp/a.txt\n/tmp/b.txt")

await run("Terminal target folder: a file resolves to its parent folder") {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let file = dir.appendingPathComponent("note.txt")
    try "hello".write(to: file, atomically: true, encoding: .utf8)

    let target = FileActionLogic.folderURL(for: file)
    guard target.standardizedFileURL.path == dir.standardizedFileURL.path else {
        throw TestFailure("expected \(dir.path), got \(target.path)")
    }
}

await run("Terminal target folder: a folder resolves to itself") {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let target = FileActionLogic.folderURL(for: dir)
    guard target.standardizedFileURL.path == dir.standardizedFileURL.path else {
        throw TestFailure("expected \(dir.path), got \(target.path)")
    }
}

print("\nMixed selections (Convert wheel)")

await run("Mixed JPEG+PNG offers only formats valid for both (not JPEG or PNG)") {
    let segments = WheelSegment.convertSegments(for: [.jpeg, .png])
    let types = Set(segments.compactMap(\.outputType))
    guard !types.contains(.jpeg), !types.contains(.png), types.contains(.heic), !segments.isEmpty else {
        throw TestFailure("got targets \(types)")
    }
}

await run("Mixed supported+unsupported type has no common targets, and doesn't crash") {
    let docx = UTType("org.openxmlformats.wordprocessingml.document")!
    let segments = WheelSegment.convertSegments(for: [.jpeg, docx])
    guard segments.isEmpty else { throw TestFailure("expected no common targets, got \(segments.count)") }
}

check("Empty input list produces no segments", WheelSegment.convertSegments(for: []).isEmpty)

print("\nAudio/Video conversions")

if !ExternalTool.ffmpeg.isAvailable || !ExternalTool.ffprobe.isAvailable {
    skip("Audio/video conversion tests", because: "ffmpeg/ffprobe not installed — can't generate fixtures")
} else {
    await run("Video to WAV to MP3, both via ffmpeg") {
        let video = try makeTestVideo()
        defer { try? FileManager.default.removeItem(at: video) }
        let wav = video.deletingPathExtension().appendingPathExtension("wav")
        defer { try? FileManager.default.removeItem(at: wav) }
        _ = try await FFmpegMediaConverter().convert(input: video, output: wav, options: ConversionOptions()) { _ in }
        guard FileManager.default.fileExists(atPath: wav.path) else { throw TestFailure("wav not created") }

        let mp3 = video.deletingPathExtension().appendingPathExtension("mp3")
        defer { try? FileManager.default.removeItem(at: mp3) }
        _ = try await FFmpegMediaConverter().convert(input: wav, output: mp3, options: ConversionOptions()) { _ in }
        let data = try Data(contentsOf: mp3)
        guard data.count > 100 else { throw TestFailure("mp3 output too small (\(data.count) bytes)") }
    }

    await run("Extract MP3 from video drops the video stream") {
        let video = try makeTestVideo()
        defer { try? FileManager.default.removeItem(at: video) }
        let mp3 = video.deletingPathExtension().appendingPathExtension("mp3")
        defer { try? FileManager.default.removeItem(at: mp3) }
        _ = try await FFmpegMediaConverter().convert(input: video, output: mp3, options: ConversionOptions()) { _ in }
        guard FileManager.default.fileExists(atPath: mp3.path) else { throw TestFailure("mp3 not created") }
    }

    await run("Video to WebM via ffmpeg") {
        let video = try makeTestVideo()
        defer { try? FileManager.default.removeItem(at: video) }
        let webm = video.deletingPathExtension().appendingPathExtension("webm")
        defer { try? FileManager.default.removeItem(at: webm) }
        _ = try await FFmpegMediaConverter().convert(input: video, output: webm, options: ConversionOptions()) { _ in }
        guard FileManager.default.fileExists(atPath: webm.path) else { throw TestFailure("webm not created") }
    }

    await run("Video to MKV via ffmpeg") {
        let video = try makeTestVideo()
        defer { try? FileManager.default.removeItem(at: video) }
        let mkv = video.deletingPathExtension().appendingPathExtension("mkv")
        defer { try? FileManager.default.removeItem(at: mkv) }
        _ = try await FFmpegMediaConverter().convert(input: video, output: mkv, options: ConversionOptions()) { _ in }
        guard FileManager.default.fileExists(atPath: mkv.path) else { throw TestFailure("mkv not created") }
    }

    await run("Audio to OGG uses Vorbis, not ffmpeg's FLAC-in-Ogg default") {
        guard let ffprobePath = ExternalTool.ffprobe.path else { throw TestFailure("ffprobe not available") }
        let video = try makeTestVideo()
        defer { try? FileManager.default.removeItem(at: video) }
        let ogg = video.deletingPathExtension().appendingPathExtension("ogg")
        defer { try? FileManager.default.removeItem(at: ogg) }
        _ = try await FFmpegMediaConverter().convert(input: video, output: ogg, options: ConversionOptions()) { _ in }

        let probe = Process()
        probe.standardInput = FileHandle.nullDevice
        probe.executableURL = URL(fileURLWithPath: ffprobePath)
        probe.arguments = ["-v", "error", "-show_entries", "stream=codec_name", "-select_streams", "a", "-of", "default=noprint_wrappers=1:nokey=1", ogg.path]
        let pipe = Pipe()
        probe.standardOutput = pipe
        try probe.run()
        probe.waitUntilExit()
        let codec = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard codec == "vorbis" else { throw TestFailure("expected vorbis, got \(codec ?? "nil")") }
    }

    await run("Video to GIF via ffmpeg produces a real GIF") {
        let video = try makeTestVideo()
        defer { try? FileManager.default.removeItem(at: video) }
        let gif = video.deletingPathExtension().appendingPathExtension("gif")
        defer { try? FileManager.default.removeItem(at: gif) }
        _ = try await FFmpegMediaConverter().convert(input: video, output: gif, options: ConversionOptions()) { _ in }
        let data = try Data(contentsOf: gif)
        guard data.starts(with: Data("GIF8".utf8)) else { throw TestFailure("output isn't a GIF") }
    }

    await run("Video to M4A via AVFoundation (audio extraction)") {
        let video = try makeTestVideo()
        defer { try? FileManager.default.removeItem(at: video) }
        let m4a = video.deletingPathExtension().appendingPathExtension("m4a")
        defer { try? FileManager.default.removeItem(at: m4a) }
        _ = try await AVFoundationMediaConverter().convert(input: video, output: m4a, options: ConversionOptions()) { _ in }
        guard FileManager.default.fileExists(atPath: m4a.path) else { throw TestFailure("m4a not created") }
    }

    await run("Video to MOV via AVFoundation") {
        let video = try makeTestVideo()
        defer { try? FileManager.default.removeItem(at: video) }
        let mov = video.deletingPathExtension().appendingPathExtension("mov")
        defer { try? FileManager.default.removeItem(at: mov) }
        do {
            _ = try await AVFoundationMediaConverter().convert(input: video, output: mov, options: ConversionOptions()) { _ in }
        } catch let error as NSError where error.domain == AVFoundationErrorDomain && error.code == -11838 {
            // Virtual machines (e.g. CI runners) have no hardware video encoder.
            skip("Video to MOV via AVFoundation", because: "no video encoder available on this machine")
            return
        }
        guard FileManager.default.fileExists(atPath: mov.path) else { throw TestFailure("mov not created") }
    }

    await run("Cancelling an in-progress conversion stops it and deletes the partial file") {
        let video = try makeTestVideo(seconds: 8)
        defer { try? FileManager.default.removeItem(at: video) }
        let webm = video.deletingPathExtension().appendingPathExtension("webm")

        let task = Task {
            _ = try await FFmpegMediaConverter().convert(input: video, output: webm, options: ConversionOptions()) { _ in }
        }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()

        do {
            try await task.value
            throw TestFailure("expected cancellation to throw")
        } catch is CancellationError {
            // expected
        } catch is TestFailure {
            throw TestFailure("expected cancellation to throw")
        } catch {
            throw TestFailure("expected CancellationError, got \(error)")
        }

        guard !FileManager.default.fileExists(atPath: webm.path) else {
            try? FileManager.default.removeItem(at: webm)
            throw TestFailure("partial output file was not deleted after cancellation")
        }
    }

    await run("Audio type doesn't offer video targets; video type's targets include MP3") {
        let audioTargets = ConverterRegistry.shared.availableTargets(for: .mp3)
        guard !audioTargets.contains(.mpeg4Movie), !audioTargets.contains(.quickTimeMovie) else {
            throw TestFailure("MP3 offered a video target: \(audioTargets)")
        }
        let videoTargets = ConverterRegistry.shared.availableTargets(for: .mpeg4Movie)
        guard videoTargets.contains(.mp3) else {
            throw TestFailure("MP4 didn't offer MP3 as an extract target: \(videoTargets)")
        }
    }
}

print("\nMilestone 6: PDF export (native, no external tool)")

await run("PDF to PNG renders at 300 DPI") {
    let pdf = try makeTestPDF(pageCount: 1)
    defer { try? FileManager.default.removeItem(at: pdf) }
    let png = pdf.deletingPathExtension().appendingPathExtension("png")
    defer { try? FileManager.default.removeItem(at: png) }

    _ = try await PDFExportConverter().convert(input: pdf, output: png, options: ConversionOptions()) { _ in }
    guard let source = CGImageSourceCreateWithURL(png as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw TestFailure("couldn't read back the PNG")
    }
    // 200x200pt page at 300 DPI (scale 300/72) should be 833x833px.
    guard image.width == 833, image.height == 833 else {
        throw TestFailure("expected 833x833, got \(image.width)x\(image.height)")
    }
}

await run("Multi-page PDF to JPG goes into a new folder, not loose files") {
    let pdf = try makeTestPDF(pageCount: 3)
    defer { try? FileManager.default.removeItem(at: pdf) }
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let jpg = dir.appendingPathComponent(pdf.deletingPathExtension().lastPathComponent).appendingPathExtension("jpg")

    let result = try await PDFExportConverter().convert(input: pdf, output: jpg, options: ConversionOptions()) { _ in }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: result.outputURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        throw TestFailure("expected a folder, got \(result.outputURL.path)")
    }
    let pages = try FileManager.default.contentsOfDirectory(at: result.outputURL, includingPropertiesForKeys: nil)
    guard pages.count == 3 else { throw TestFailure("expected 3 page images, found \(pages.count)") }
    guard !FileManager.default.fileExists(atPath: jpg.path) else {
        throw TestFailure("a loose file was also left at the originally-planned path")
    }
}

await run("PDF to TXT extracts real text content") {
    let pdf = try makeTestPDF(pageCount: 1, text: "Mandarin self-test marker QWERTY123", pageWidth: 500)
    defer { try? FileManager.default.removeItem(at: pdf) }
    let txt = pdf.deletingPathExtension().appendingPathExtension("txt")
    defer { try? FileManager.default.removeItem(at: txt) }

    _ = try await PDFExportConverter().convert(input: pdf, output: txt, options: ConversionOptions()) { _ in }
    let text = try String(contentsOf: txt, encoding: .utf8)
    guard text.contains("QWERTY123") else { throw TestFailure("extracted text didn't contain the marker: \(text)") }
}

print("\nMilestone 6: Documents (native NSAttributedString)")

await run("TXT to DOCX to TXT round-trips the text exactly") {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let original = "Round trip test paragraph one.\nParagraph two."
    let txt = dir.appendingPathComponent("doc.txt")
    try original.write(to: txt, atomically: true, encoding: .utf8)

    let docx = dir.appendingPathComponent("doc.docx")
    _ = try await NativeDocumentConverter().convert(input: txt, output: docx, options: ConversionOptions()) { _ in }
    let backToTxt = dir.appendingPathComponent("doc2.txt")
    _ = try await NativeDocumentConverter().convert(input: docx, output: backToTxt, options: ConversionOptions()) { _ in }

    // NSAttributedString's plain-text export always appends a trailing
    // newline — a harmless normalization, not data loss, so tolerate it.
    let roundTripped = try String(contentsOf: backToTxt, encoding: .utf8)
        .trimmingCharacters(in: .newlines)
    guard roundTripped == original else {
        throw TestFailure("expected \"\(original)\", got \"\(roundTripped)\"")
    }
}

await run("RTF to HTML produces real HTML") {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    // Build the RTF fixture natively (same machinery NativeDocumentConverter
    // itself uses), rather than depending on an external tool just to set
    // up the test.
    let rtfText = NSAttributedString(string: "Hello RTF")
    let rtfData = try rtfText.data(from: NSRange(location: 0, length: rtfText.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    let rtf = dir.appendingPathComponent("note.rtf")
    try rtfData.write(to: rtf)

    let html = dir.appendingPathComponent("note.html")
    _ = try await NativeDocumentConverter().convert(input: rtf, output: html, options: ConversionOptions()) { _ in }
    let htmlText = try String(contentsOf: html, encoding: .utf8)
    guard htmlText.contains("<html>"), htmlText.contains("Hello RTF") else {
        throw TestFailure("output doesn't look like HTML: \(htmlText.prefix(200))")
    }
}

check("PAGES has no Convert targets — no tool here can write it", {
    ConverterRegistry.shared.availableTargets(for: UTType(filenameExtension: "pages")!).isEmpty
}())

if ExternalTool.pandoc.isAvailable {
    await run("TXT to Markdown to EPUB via pandoc") {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let txt = dir.appendingPathComponent("doc.txt")
        try "Pandoc bridge test content.".write(to: txt, atomically: true, encoding: .utf8)
        let md = dir.appendingPathComponent("doc.md")
        _ = try await PandocDocumentConverter().convert(input: txt, output: md, options: ConversionOptions()) { _ in }
        let epub = dir.appendingPathComponent("doc.epub")
        let result = try await PandocDocumentConverter().convert(input: md, output: epub, options: ConversionOptions()) { _ in }
        guard result.warning != nil else { throw TestFailure("expected a best-effort warning for EPUB") }
        let data = try Data(contentsOf: epub)
        guard data.count > 100 else { throw TestFailure("epub output too small") }
    }
} else {
    skip("TXT to Markdown to EPUB via pandoc", because: "pandoc not installed")
}

print("\nMilestone 6: Spreadsheets")

await run("CSV to TSV to CSV round-trips byte-for-byte") {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let original = "name,age,city\nAlice,30,NYC\nBob,25,LA\n"
    let csv = dir.appendingPathComponent("data.csv")
    try original.write(to: csv, atomically: true, encoding: .utf8)
    let tsv = dir.appendingPathComponent("data.tsv")
    _ = try await CSVTSVConverter().convert(input: csv, output: tsv, options: ConversionOptions()) { _ in }
    let backToCSV = dir.appendingPathComponent("data2.csv")
    _ = try await CSVTSVConverter().convert(input: tsv, output: backToCSV, options: ConversionOptions()) { _ in }

    let roundTripped = try String(contentsOf: backToCSV, encoding: .utf8)
    guard roundTripped == original else {
        throw TestFailure("expected \"\(original)\", got \"\(roundTripped)\"")
    }
}

await run("CSV with quoted, comma-containing fields parses correctly") {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let csv = dir.appendingPathComponent("quoted.csv")
    try "name,note\n\"Smith, John\",\"Says \"\"hi\"\"\"\n".write(to: csv, atomically: true, encoding: .utf8)
    let tsvURL = dir.appendingPathComponent("quoted.tsv")
    _ = try await CSVTSVConverter().convert(input: csv, output: tsvURL, options: ConversionOptions()) { _ in }
    let tsv = try String(contentsOf: tsvURL, encoding: .utf8)
    guard tsv.contains("Smith, John"), tsv.contains("Says \"hi\"") else {
        throw TestFailure("quoted fields weren't parsed correctly: \(tsv)")
    }
}

if ExternalTool.soffice.isAvailable {
    await run("CSV to XLSX to CSV via LibreOffice preserves the data") {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let csv = dir.appendingPathComponent("data.csv")
        try "name,age\nAlice,30\nBob,25\n".write(to: csv, atomically: true, encoding: .utf8)
        let xlsx = dir.appendingPathComponent("data.xlsx")
        _ = try await LibreOfficeConverter().convert(input: csv, output: xlsx, options: ConversionOptions()) { _ in }
        guard FileManager.default.fileExists(atPath: xlsx.path) else { throw TestFailure("xlsx not created") }

        let backToCSV = dir.appendingPathComponent("data2.csv")
        _ = try await LibreOfficeConverter().convert(input: xlsx, output: backToCSV, options: ConversionOptions()) { _ in }
        let text = try String(contentsOf: backToCSV, encoding: .utf8)
        guard text.contains("Alice") && text.contains("30") && text.contains("Bob") else {
            throw TestFailure("data lost in round trip: \(text)")
        }
    }

    await run("A corrupted XLSX fails clearly, not silently") {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fakeXLSX = dir.appendingPathComponent("fake.xlsx")
        try "not a real spreadsheet".write(to: fakeXLSX, atomically: true, encoding: .utf8)
        let csv = dir.appendingPathComponent("fake.csv")

        var didFail = false
        do {
            _ = try await LibreOfficeConverter().convert(input: fakeXLSX, output: csv, options: ConversionOptions()) { _ in }
        } catch {
            didFail = true
        }
        guard didFail else { throw TestFailure("expected a clear failure for a corrupted XLSX") }
        guard !FileManager.default.fileExists(atPath: csv.path) else { throw TestFailure("left a garbage output file behind") }
    }
} else {
    skip("Spreadsheet tests (LibreOffice)", because: "soffice not installed")
}

print("\nMilestone 6: Slides")

if ExternalTool.soffice.isAvailable, ExternalTool.pandoc.isAvailable {
    await run("PPTX to PDF preserves every slide as its own page") {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let md = dir.appendingPathComponent("slides.md")
        try "# Slide One\n\nContent\n\n# Slide Two\n\nMore content\n".write(to: md, atomically: true, encoding: .utf8)
        let pptx = dir.appendingPathComponent("slides.pptx")
        _ = try await PandocDocumentConverter().convert(input: md, output: pptx, options: ConversionOptions()) { _ in }

        let pdf = dir.appendingPathComponent("slides.pdf")
        let result = try await LibreOfficeConverter().convert(input: pptx, output: pdf, options: ConversionOptions()) { _ in }
        guard result.warning != nil else { throw TestFailure("expected a best-effort warning") }
        guard let document = PDFDocument(url: result.outputURL) else { throw TestFailure("couldn't read back the PDF") }
        guard document.pageCount == 2 else { throw TestFailure("expected 2 pages, got \(document.pageCount)") }
    }

    await run("PPTX to PNG exports every slide into a folder (not just the first)") {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let md = dir.appendingPathComponent("slides.md")
        try "# Slide One\n\nContent\n\n# Slide Two\n\nMore content\n".write(to: md, atomically: true, encoding: .utf8)
        let pptx = dir.appendingPathComponent("slides.pptx")
        _ = try await PandocDocumentConverter().convert(input: md, output: pptx, options: ConversionOptions()) { _ in }

        let png = dir.appendingPathComponent("slides.png")
        let result = try await LibreOfficeConverter().convert(input: pptx, output: png, options: ConversionOptions()) { _ in }
        let pages = try FileManager.default.contentsOfDirectory(at: result.outputURL, includingPropertiesForKeys: nil)
        guard pages.count == 2 else { throw TestFailure("expected 2 slide images, found \(pages.count)") }
    }
} else {
    skip("Slide tests (LibreOffice + pandoc)", because: "soffice or pandoc not installed")
}

print("\nMilestone 6: Subtitles (native)")

await run("SRT to VTT to SRT round-trips exactly") {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let original = "1\n00:00:00,000 --> 00:00:02,000\nHello world\n\n2\n00:00:02,500 --> 00:00:04,000\nSecond line\n"
    let srt = dir.appendingPathComponent("subs.srt")
    try original.write(to: srt, atomically: true, encoding: .utf8)
    let vtt = dir.appendingPathComponent("subs.vtt")
    _ = try await SubtitleConverter().convert(input: srt, output: vtt, options: ConversionOptions()) { _ in }
    let backToSRT = dir.appendingPathComponent("subs2.srt")
    _ = try await SubtitleConverter().convert(input: vtt, output: backToSRT, options: ConversionOptions()) { _ in }

    let roundTripped = try String(contentsOf: backToSRT, encoding: .utf8)
    guard roundTripped == original else {
        throw TestFailure("expected \"\(original)\", got \"\(roundTripped)\"")
    }
}

await run("SRT to TXT strips timestamps, keeps the text") {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let srt = dir.appendingPathComponent("subs.srt")
    try "1\n00:00:00,000 --> 00:00:02,000\nHello world\n".write(to: srt, atomically: true, encoding: .utf8)
    let txt = dir.appendingPathComponent("subs.txt")
    _ = try await SubtitleConverter().convert(input: srt, output: txt, options: ConversionOptions()) { _ in }
    let text = try String(contentsOf: txt, encoding: .utf8)
    guard text.contains("Hello world"), !text.contains("-->") else {
        throw TestFailure("expected plain text without timestamps: \(text)")
    }
}

print("\nMilestone 6: Archives")

if ExternalTool.unar.isAvailable {
    await run("ZIP to TAR re-archives the actual contents (not the zip file itself)") {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let a = dir.appendingPathComponent("a.txt")
        let b = dir.appendingPathComponent("b.txt")
        try "file one".write(to: a, atomically: true, encoding: .utf8)
        try "file two".write(to: b, atomically: true, encoding: .utf8)

        let zip = dir.appendingPathComponent("original.zip")
        let zipProcess = Process()
        zipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipProcess.arguments = ["-q", "-j", zip.path, a.path, b.path]
        try zipProcess.run()
        zipProcess.waitUntilExit()

        let tar = dir.appendingPathComponent("original.tar")
        _ = try await ArchiveConverter().convert(input: zip, output: tar, options: ConversionOptions()) { _ in }

        let listProcess = Process()
        listProcess.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        listProcess.arguments = ["-tf", tar.path]
        let pipe = Pipe()
        listProcess.standardOutput = pipe
        try listProcess.run()
        listProcess.waitUntilExit()
        let listing = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard listing.contains("a.txt"), listing.contains("b.txt"), !listing.contains("original.zip") else {
            throw TestFailure("expected a.txt/b.txt at top level, got: \(listing)")
        }
    }

    await run("TAR to GZIP of multiple files is named .tar.gz, not bare .gz") {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let a = dir.appendingPathComponent("a.txt")
        let b = dir.appendingPathComponent("b.txt")
        try "file one".write(to: a, atomically: true, encoding: .utf8)
        try "file two".write(to: b, atomically: true, encoding: .utf8)
        let tar = dir.appendingPathComponent("original.tar")
        let tarProcess = Process()
        tarProcess.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tarProcess.arguments = ["-cf", tar.path, "-C", dir.path, "a.txt", "b.txt"]
        try tarProcess.run()
        tarProcess.waitUntilExit()

        let plannedGz = dir.appendingPathComponent("original.gz")
        let result = try await ArchiveConverter().convert(input: tar, output: plannedGz, options: ConversionOptions()) { _ in }
        guard result.outputURL.lastPathComponent == "original.tar.gz" else {
            throw TestFailure("expected original.tar.gz, got \(result.outputURL.lastPathComponent)")
        }
    }

    await run("A fake RAR fails with a clear error, not a crash") {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fakeRAR = dir.appendingPathComponent("fake.rar")
        try "not a real rar archive".write(to: fakeRAR, atomically: true, encoding: .utf8)
        let zip = dir.appendingPathComponent("fake.zip")

        var didFail = false
        do {
            _ = try await ArchiveConverter().convert(input: fakeRAR, output: zip, options: ConversionOptions()) { _ in }
        } catch {
            didFail = true
        }
        guard didFail else { throw TestFailure("expected a clear failure for a fake RAR") }
    }
} else {
    skip("Archive tests (unar)", because: "unar not installed")
}

print("\nMilestone 6: wheel crowding")

await run("No sampled file type offers more than 8 Convert targets") {
    let samples: [UTType] = [.jpeg, .mp3, .mpeg4Movie, DocumentFormats.docx, .plainText, SpreadsheetFormats.xlsx, .commaSeparatedText, SubtitleFormats.srt, .zip]
    for type in samples {
        let count = ConverterRegistry.shared.availableTargets(for: type).count
        guard count <= 8 else {
            throw TestFailure("\(type.identifier) has \(count) targets — wheel would be crowded")
        }
    }
}

print("\nMilestone 7: FileTool selection logic")

check("Image file offers only image tools plus universal Compress Archive", {
    let tools = FileTool.tools(for: .jpeg, selectionCount: 1)
    return tools.contains(.resizeImage) && tools.contains(.compressArchive) && !tools.contains(.trimVideo)
}())

check("GIF is treated as video (not image) for File Tools, matching MediaFormats", {
    let tools = FileTool.tools(for: .gif, selectionCount: 1)
    return tools.contains(.trimVideo) && !tools.contains(.cropImage)
}())

check("Merge Video only appears with 2+ files selected", {
    let singleFile = FileTool.tools(for: .mpeg4Movie, selectionCount: 1)
    let multiFile = FileTool.tools(for: .mpeg4Movie, selectionCount: 2)
    return !singleFile.contains(.mergeVideo) && multiFile.contains(.mergeVideo)
}())

check("PDF offers PDF tools, not image/video tools", {
    let tools = FileTool.tools(for: .pdf, selectionCount: 1)
    return tools.contains(.rotatePDF) && tools.contains(.mergePDF) == false && !tools.contains(.resizeImage)
}())

check("An unrecognized type still offers Compress Archive (universal)", {
    FileTool.tools(for: UTType(filenameExtension: "pages")!, selectionCount: 1) == [.compressArchive]
}())

print("\nMilestone 7: pure helper functions")

check("parsePageRange handles ranges, commas, and out-of-bounds values", {
    FileToolPDF.parsePageRange("1-3,5,99", pageCount: 6) == [1, 2, 3, 5]
}())

check("parsePageRange with garbage input returns empty, not a crash", {
    FileToolPDF.parsePageRange("not a range", pageCount: 10).isEmpty
}())

check("rotationFilter uses lossless transpose for 90/180/270", {
    FileToolMediaArgs.rotationFilter(degrees: 90) == ["-vf", "transpose=1"]
        && FileToolMediaArgs.rotationFilter(degrees: 270) == ["-vf", "transpose=2"]
        && FileToolMediaArgs.rotationFilter(degrees: 0).isEmpty
}())

check("rotationFilter falls back to the rotate filter for an arbitrary angle", {
    let args = FileToolMediaArgs.rotationFilter(degrees: 45)
    return args.first == "-vf" && (args.last?.hasPrefix("rotate=") ?? false)
}())

await run("Image resize produces the exact requested dimensions") {
    let image = makeTestCGImage(width: 50, height: 50)
    let resized = try FileToolImaging.resize(image, width: 20, height: 10)
    guard resized.width == 20, resized.height == 10 else {
        throw TestFailure("expected 20x10, got \(resized.width)x\(resized.height)")
    }
}

await run("Image crop extracts the requested region") {
    let image = makeTestCGImage(width: 50, height: 50)
    let cropped = try FileToolImaging.crop(image, x: 5, y: 5, width: 10, height: 10)
    guard cropped.width == 10, cropped.height == 10 else {
        throw TestFailure("expected 10x10, got \(cropped.width)x\(cropped.height)")
    }
}

await run("Image crop outside the image bounds fails clearly") {
    let image = makeTestCGImage(width: 10, height: 10)
    var didFail = false
    do {
        _ = try FileToolImaging.crop(image, x: 1000, y: 1000, width: 10, height: 10)
    } catch {
        didFail = true
    }
    guard didFail else { throw TestFailure("expected a clear failure for an out-of-bounds crop") }
}

await run("Image rotate by 90 degrees swaps width and height") {
    let image = makeTestCGImage(width: 40, height: 20)
    let rotated = try FileToolImaging.rotate(image, degrees: 90)
    guard rotated.width == 20, rotated.height == 40 else {
        throw TestFailure("expected 20x40, got \(rotated.width)x\(rotated.height)")
    }
}

await run("Image grayscale drops color information") {
    let image = makeTestCGImage(width: 10, height: 10) // solid red
    let gray = try FileToolImaging.grayscale(image)
    guard gray.colorSpace?.model == .monochrome else {
        throw TestFailure("expected a monochrome color space, got \(String(describing: gray.colorSpace?.model))")
    }
}

print("\nMilestone 7: end-to-end File Tool runs (via JobQueue, same as a real drop)")

await run("Resize Image tool, through FileToolRunner + JobQueue") {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let input = dir.appendingPathComponent("photo.png")
    guard let destination = CGImageDestinationCreateWithURL(input as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw TestFailure("couldn't create fixture")
    }
    CGImageDestinationAddImage(destination, makeTestCGImage(width: 100, height: 100), nil)
    CGImageDestinationFinalize(destination)

    let settingsStore = SettingsStore()

    settingsStore.customOutputFolderPath = nil // never trust leftover state from a prior test's UserDefaults
    let jobQueue = JobQueue(settingsStore: settingsStore)
    let runner = FileToolRunner(jobQueue: jobQueue)
    var parameters = ToolParameterValues()
    parameters.numbers["width"] = 30
    parameters.numbers["height"] = 20
    runner.perform(.resizeImage, on: [input], parameters: parameters)

    guard let job = jobQueue.jobs.last else { throw TestFailure("job not created") }
    try await waitForJob(job)
    guard case .succeeded(_, let revealURL) = job.state, let revealURL else {
        throw TestFailure("expected success, got \(job.state)")
    }
    guard let source = CGImageSourceCreateWithURL(revealURL as CFURL, nil),
          let resultImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw TestFailure("couldn't read back the resized image")
    }
    guard resultImage.width == 30, resultImage.height == 20 else {
        throw TestFailure("expected 30x20, got \(resultImage.width)x\(resultImage.height)")
    }
}

if ExternalTool.ffmpeg.isAvailable {
    await run("Trim Video tool, through FileToolRunner + JobQueue") {
        let video = try makeTestVideo(seconds: 3)
        defer { try? FileManager.default.removeItem(at: video) }

        let settingsStore = SettingsStore()

        settingsStore.customOutputFolderPath = nil // never trust leftover state from a prior test's UserDefaults
        let jobQueue = JobQueue(settingsStore: settingsStore)
        let runner = FileToolRunner(jobQueue: jobQueue)
        var parameters = ToolParameterValues()
        parameters.numbers["start"] = 0
        parameters.numbers["end"] = 1
        runner.perform(.trimVideo, on: [video], parameters: parameters)

        guard let job = jobQueue.jobs.last else { throw TestFailure("job not created") }
        try await waitForJob(job)
        guard case .succeeded(_, let revealURL) = job.state, let revealURL else {
            throw TestFailure("expected success, got \(job.state)")
        }
        guard let duration = FileToolMediaArgs.probeDuration(of: revealURL) else {
            throw TestFailure("couldn't probe trimmed video duration")
        }
        guard duration < 2 else { throw TestFailure("expected a ~1s trimmed video, got \(duration)s") }
    }

    await run("Cancelling a File Tool run stops it and deletes the partial file") {
        // Long and high-res enough that compressing it takes a couple of
        // real seconds (measured: an 8s/320x240 clip compresses in ~0.1s —
        // too fast for a 300ms cancel to ever land).
        let video = try makeTestVideo(seconds: 60, size: "1280x720")
        defer { try? FileManager.default.removeItem(at: video) }

        let settingsStore = SettingsStore()

        settingsStore.customOutputFolderPath = nil // never trust leftover state from a prior test's UserDefaults
        let jobQueue = JobQueue(settingsStore: settingsStore)
        let runner = FileToolRunner(jobQueue: jobQueue)
        var parameters = ToolParameterValues()
        parameters.numbers["quality"] = 0.5 // unused by compressVideo, harmless
        runner.perform(.compressVideo, on: [video], parameters: parameters)

        guard let job = jobQueue.jobs.last else { throw TestFailure("job not created") }
        try await Task.sleep(for: .milliseconds(300))
        jobQueue.cancel(job)
        try await waitForJob(job)
        guard case .cancelled = job.state else { throw TestFailure("expected cancelled, got \(job.state)") }
    }
} else {
    skip("Video File Tool tests", because: "ffmpeg not installed")
}

await run("Rotate PDF tool, through FileToolRunner + JobQueue") {
    let pdf = try makeTestPDF(pageCount: 1)
    defer { try? FileManager.default.removeItem(at: pdf) }

    let settingsStore = SettingsStore()

    settingsStore.customOutputFolderPath = nil // never trust leftover state from a prior test's UserDefaults
    let jobQueue = JobQueue(settingsStore: settingsStore)
    let runner = FileToolRunner(jobQueue: jobQueue)
    var parameters = ToolParameterValues()
    parameters.numbers["degrees"] = 90
    runner.perform(.rotatePDF, on: [pdf], parameters: parameters)

    guard let job = jobQueue.jobs.last else { throw TestFailure("job not created") }
    try await waitForJob(job)
    guard case .succeeded(_, let revealURL) = job.state, let revealURL,
          let document = PDFDocument(url: revealURL), let page = document.page(at: 0) else {
        throw TestFailure("expected success, got \(job.state)")
    }
    guard page.rotation == 90 else { throw TestFailure("expected rotation 90, got \(page.rotation)") }
}

await run("Extract Pages PDF tool produces a PDF with just the requested pages") {
    let pdf = try makeTestPDF(pageCount: 3)
    defer { try? FileManager.default.removeItem(at: pdf) }

    let settingsStore = SettingsStore()

    settingsStore.customOutputFolderPath = nil // never trust leftover state from a prior test's UserDefaults
    let jobQueue = JobQueue(settingsStore: settingsStore)
    let runner = FileToolRunner(jobQueue: jobQueue)
    var parameters = ToolParameterValues()
    parameters.strings["pages"] = "2"
    runner.perform(.extractPagesPDF, on: [pdf], parameters: parameters)

    guard let job = jobQueue.jobs.last else { throw TestFailure("job not created") }
    try await waitForJob(job)
    guard case .succeeded(_, let revealURL) = job.state, let revealURL,
          let document = PDFDocument(url: revealURL) else {
        throw TestFailure("expected success, got \(job.state)")
    }
    guard document.pageCount == 1 else { throw TestFailure("expected 1 extracted page, got \(document.pageCount)") }
}

await run("Split PDF produces one file per page in a new folder") {
    let pdf = try makeTestPDF(pageCount: 3)
    defer { try? FileManager.default.removeItem(at: pdf) }

    let settingsStore = SettingsStore()

    settingsStore.customOutputFolderPath = nil // never trust leftover state from a prior test's UserDefaults
    let jobQueue = JobQueue(settingsStore: settingsStore)
    let runner = FileToolRunner(jobQueue: jobQueue)
    runner.perform(.splitPDF, on: [pdf], parameters: ToolParameterValues())

    guard let job = jobQueue.jobs.last else { throw TestFailure("job not created") }
    try await waitForJob(job)
    guard case .succeeded(_, let revealURL) = job.state, let revealURL else {
        throw TestFailure("expected success, got \(job.state)")
    }
    let pages = try FileManager.default.contentsOfDirectory(at: revealURL, includingPropertiesForKeys: nil)
    guard pages.count == 3 else { throw TestFailure("expected 3 page files, found \(pages.count)") }
}

await run("Merge PDF combines multiple files into one, in order") {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let first = try makeTestPDF(pageCount: 1, text: "First document")
    let second = try makeTestPDF(pageCount: 2, text: "Second document")
    defer {
        try? FileManager.default.removeItem(at: first)
        try? FileManager.default.removeItem(at: second)
    }

    let settingsStore = SettingsStore()

    settingsStore.customOutputFolderPath = nil // never trust leftover state from a prior test's UserDefaults
    settingsStore.customOutputFolderPath = dir.path
    let jobQueue = JobQueue(settingsStore: settingsStore)
    let runner = FileToolRunner(jobQueue: jobQueue)
    runner.perform(.mergePDF, on: [first, second], parameters: ToolParameterValues())

    guard let job = jobQueue.jobs.last else { throw TestFailure("job not created") }
    try await waitForJob(job)
    guard case .succeeded(_, let revealURL) = job.state, let revealURL,
          let merged = PDFDocument(url: revealURL) else {
        throw TestFailure("expected success, got \(job.state)")
    }
    guard merged.pageCount == 3 else { throw TestFailure("expected 3 total pages, got \(merged.pageCount)") }
}

await run("Compress (Archive) File Tool zips the dropped file") {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("note.txt")
    try "hello".write(to: file, atomically: true, encoding: .utf8)

    let settingsStore = SettingsStore()

    settingsStore.customOutputFolderPath = nil // never trust leftover state from a prior test's UserDefaults
    let jobQueue = JobQueue(settingsStore: settingsStore)
    let runner = FileToolRunner(jobQueue: jobQueue)
    runner.perform(.compressArchive, on: [file], parameters: ToolParameterValues())

    guard let job = jobQueue.jobs.last else { throw TestFailure("job not created") }
    try await waitForJob(job)
    guard case .succeeded(_, let revealURL) = job.state, let revealURL else {
        throw TestFailure("expected success, got \(job.state)")
    }
    guard revealURL.pathExtension == "zip" else { throw TestFailure("expected a .zip, got \(revealURL.lastPathComponent)") }
}

print("\nMilestone 8: Settings — enable/disable formats")

await run("Disabling then re-enabling a format round-trips correctly") {
    let settingsStore = SettingsStore()
    settingsStore.customOutputFolderPath = nil // never trust leftover state from a prior test's UserDefaults
    let originallyEnabled = settingsStore.isFormatEnabled(.png)
    defer { settingsStore.setFormat(.png, enabled: originallyEnabled) }

    settingsStore.setFormat(.png, enabled: false)
    guard !settingsStore.isFormatEnabled(.png) else { throw TestFailure("expected PNG to be disabled") }

    settingsStore.setFormat(.png, enabled: true)
    guard settingsStore.isFormatEnabled(.png) else { throw TestFailure("expected PNG to be enabled again") }
}

check("A freshly created SettingsStore has every format enabled by default", {
    let settingsStore = SettingsStore()
    return settingsStore.isFormatEnabled(.png) && settingsStore.isFormatEnabled(.jpeg) && settingsStore.isFormatEnabled(.mp3)
}())

print("\nMilestone 8: VoiceOver label disambiguation")

check("Compress Image and Compress Archive share a visual title but not an accessibility label", {
    FileTool.compressImage.title == FileTool.compressArchive.title
        && FileTool.compressImage.accessibilityLabel != FileTool.compressArchive.accessibilityLabel
}())

check("Every FileTool has a non-empty, distinct accessibility label", {
    let labels = FileTool.allCases.map(\.accessibilityLabel)
    return Set(labels).count == FileTool.allCases.count && labels.allSatisfy { !$0.isEmpty }
}())

await runReleaseTests()
await runEditorTests()

print("\n\(totalCount - failureCount)/\(totalCount) passed")
exit(failureCount == 0 ? 0 : 1)
