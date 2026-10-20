import AppKit
import Foundation
import ImageIO
import Mandarin
import PDFKit
import UniformTypeIdentifiers

// MARK: - Fixtures

typealias RGBA = (r: Int, g: Int, b: Int, a: Int)

/// Four coloured quadrants: TL red, TR green, BL blue, BR yellow.
func makeQuadrantImage(width: Int = 200, height: Int = 100) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    func fill(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ rect: CGRect) {
        context.setFillColor(CGColor(srgbRed: r, green: g, blue: b, alpha: 1))
        context.fill(rect)
    }
    let hw = CGFloat(width) / 2, hh = CGFloat(height) / 2
    fill(1, 0, 0, CGRect(x: 0, y: hh, width: hw, height: hh))        // TL (CG origin is bottom-left)
    fill(0, 1, 0, CGRect(x: hw, y: hh, width: hw, height: hh))       // TR
    fill(0, 0, 1, CGRect(x: 0, y: 0, width: hw, height: hh))         // BL
    fill(1, 1, 0, CGRect(x: hw, y: 0, width: hw, height: hh))        // BR
    return context.makeImage()!
}

/// Pixel at (x, y) with a top-left origin.
func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> RGBA {
    var data = [UInt8](repeating: 0, count: 4)
    let context = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return (Int(data[0]), Int(data[1]), Int(data[2]), Int(data[3]))
}

func isColor(_ p: RGBA, _ r: Int, _ g: Int, _ b: Int, tolerance: Int = 12) -> Bool {
    abs(p.r - r) <= tolerance && abs(p.g - g) <= tolerance && abs(p.b - b) <= tolerance
}

func writeImage(_ image: CGImage, type: UTType, name: String? = nil, in folder: URL? = nil) throws -> URL {
    let dir = folder ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent(name ?? "photo.\(type.preferredFilenameExtension ?? "png")")
    guard let d = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { throw TestFailure("no destination") }
    CGImageDestinationAddImage(d, image, nil)
    guard CGImageDestinationFinalize(d) else { throw TestFailure("couldn't write fixture") }
    return url
}

func imageSize(at url: URL) -> (Int, Int)? {
    guard let s = CGImageSourceCreateWithURL(url as CFURL, nil),
          let p = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any],
          let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int else { return nil }
    return (w, h)
}

func near(_ a: CGFloat, _ b: CGFloat, _ eps: CGFloat = 0.01) -> Bool { abs(a - b) <= eps }

// MARK: - Runner

@MainActor
func runEditorTests() async {
    await runPhotoEditorTests()
    await runPDFPageTests()
    await runBackgroundTests()
    await runAudioTests()
    await runVideoTests()
    await runEditorSnapshotTests()
}

@MainActor
func runPhotoEditorTests() async {
    print("\nEditors: crop geometry")

    let bounds = CGSize(width: 1000, height: 600)
    check("fit() centres content in the container", {
        let r = CropGeometry.fit(content: CGSize(width: 200, height: 100), in: CGSize(width: 400, height: 400))
        return near(r.width, 400) && near(r.height, 200) && near(r.minY, 100)
    }())
    check("initialRect with 16:9 is the largest centred 16:9 box", {
        let r = CropGeometry.initialRect(in: bounds, ratio: 16.0 / 9)
        return near(r.width / r.height, 16.0 / 9, 0.001) && near(r.width, 1000) && near(r.midY, 300)
    }())
    check("initialRect with a free box is everything", CropGeometry.initialRect(in: bounds, ratio: nil) == CGRect(origin: .zero, size: bounds))
    check("1:1 preset on a landscape box gives a centred square", {
        let r = CropGeometry.initialRect(in: bounds, ratio: 1)
        return near(r.width, 600) && near(r.height, 600) && near(r.midX, 500)
    }())
    check("moving stops at the edges", {
        let r = CropGeometry.moved(CGRect(x: 100, y: 100, width: 200, height: 100), by: CGSize(width: 5000, height: -5000), in: bounds)
        return r == CGRect(x: 800, y: 0, width: 200, height: 100)
    }())
    check("free corner drag resizes from the opposite corner", {
        let r = CropGeometry.dragged(CGRect(x: 100, y: 100, width: 200, height: 100), handle: .bottomRight,
                                     delta: CGSize(width: 50, height: 30), ratio: nil, in: bounds)
        return r == CGRect(x: 100, y: 100, width: 250, height: 130)
    }())
    check("dragging a handle past the opposite edge keeps the minimum size", {
        let r = CropGeometry.dragged(CGRect(x: 100, y: 100, width: 200, height: 100), handle: .right,
                                     delta: CGSize(width: -900, height: 0), ratio: nil, in: bounds, minSize: 8)
        return near(r.width, 8) && near(r.minX, 100)
    }())
    check("ratio-locked corner drag keeps the ratio and the anchor", {
        let start = CGRect(x: 100, y: 100, width: 320, height: 180)
        let r = CropGeometry.dragged(start, handle: .bottomRight, delta: CGSize(width: 160, height: 5), ratio: 16.0 / 9, in: bounds)
        return near(r.width / r.height, 16.0 / 9, 0.001) && near(r.minX, 100) && near(r.minY, 100) && r.width > 320
    }())
    check("hit testing prefers handles, then body, else nil", {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        return CropGeometry.handle(at: CGPoint(x: 101, y: 99), in: r) == .topLeft
            && CropGeometry.handle(at: CGPoint(x: 200, y: 200), in: r) == .bottom
            && CropGeometry.handle(at: CGPoint(x: 300, y: 150), in: r) == .right
            && CropGeometry.handle(at: CGPoint(x: 200, y: 150), in: r) == .body
            && CropGeometry.handle(at: CGPoint(x: 600, y: 500), in: r) == nil
    }())
    check("fuzz: 3000 random drags always stay inside bounds and keep the ratio", {
        var rng = SystemRandomNumberGenerator()
        let handles: [CropHandle] = [.topLeft, .top, .topRight, .right, .bottomRight, .bottom, .bottomLeft, .left, .body]
        let ratios: [CGFloat?] = [nil, 1, 4.0 / 3, 16.0 / 9, 9.0 / 16, 2.0 / 3]
        for _ in 0..<3000 {
            let ratio = ratios.randomElement(using: &rng)!
            let start = CropGeometry.applying(ratio: ratio, to: CGRect(x: .random(in: 0...300, using: &rng), y: .random(in: 0...200, using: &rng),
                                                                         width: .random(in: 100...600, using: &rng), height: .random(in: 80...300, using: &rng)), in: bounds)
            let handle = handles.randomElement(using: &rng)!
            let delta = CGSize(width: .random(in: -1500...1500, using: &rng), height: .random(in: -1200...1200, using: &rng))
            let r = CropGeometry.dragged(start, handle: handle, delta: delta, ratio: ratio, in: bounds)
            let eps: CGFloat = 0.001
            if r.minX < -eps || r.minY < -eps || r.maxX > bounds.width + eps || r.maxY > bounds.height + eps { return false }
            if r.width < 1 || r.height < 1 { return false }
            if let ratio, handle != .body, abs(r.width / r.height - ratio) > 0.01 { return false }
        }
        return true
    }())
    check("pixelAligned rounds to whole pixels inside bounds", {
        let r = CropGeometry.pixelAligned(CGRect(x: 10.4, y: 20.6, width: 99.7, height: 50.2), in: CGSize(width: 111, height: 100))
        return r.minX == 10 && r.minY == 21 && r.width == 100 && r.height == 50 && r.maxX <= 111
    }())
    check("aspect presets: ratios, original and free", {
        AspectPreset.free.ratio(originalSize: .init(width: 4, height: 3)) == nil
            && near(AspectPreset.original.ratio(originalSize: .init(width: 400, height: 300))!, 4.0 / 3, 0.0001)
            && near(AspectPreset.r9x16.ratio(originalSize: .zero)!, 0.5625, 0.0001)
    }())
    check("linked resize keeps the proportions", ResizeMath.height(forWidth: 800, ratio: 4.0 / 3) == 600 && ResizeMath.width(forHeight: 90, ratio: 16.0 / 9) == 160 && ResizeMath.height(forWidth: 1, ratio: 100) == 1)

    print("\nEditors: shared helpers")
    check("Every ffmpeg launch gets -nostdin exactly once", ExternalTool.ffmpegArguments(["-i", "a"]) == ["-nostdin", "-i", "a"] && ExternalTool.ffmpegArguments(["-nostdin", "-i", "a"]) == ["-nostdin", "-i", "a"])
    check("TimeText parses seconds, m:ss and h:mm:ss and rejects junk",
          TimeText.parse("83.5") == 83.5 && TimeText.parse("1:23.5") == 83.5 && TimeText.parse("1:01:01") == 3661
          && TimeText.parse("abc") == nil && TimeText.parse("-3") == nil && TimeText.parse("1:2:3:4") == nil && TimeText.parse("0,5") == 0.5)
    check("TimeText formats with milliseconds", TimeText.format(83.5) == "1:23.500" && TimeText.format(3661.25) == "1:01:01.250" && TimeText.format(-4) == "0:00.000")
    check("TimeText round-trips", {
        for v in [0.0, 0.001, 59.999, 61.5, 3599.123] { if abs((TimeText.parse(TimeText.format(v)) ?? -1) - v) > 0.0006 { return false } }
        return true
    }())
    check("TrimRange keeps start < end inside the duration", {
        var t = TrimRange(duration: 10)
        t.setStart(4); t.setEnd(6)
        let ok1 = t.start == 4 && t.end == 6 && t.length == 2 && !t.isFull
        t.setStart(9.99)                         // can't pass the end
        let ok2 = t.start <= t.end - TrimRange.minimumLength + 1e-9
        t.setEnd(-5)                             // can't pass the start
        let ok3 = t.end >= t.start + TrimRange.minimumLength - 1e-9 || t.end >= t.start
        t.setEnd(99)
        return ok1 && ok2 && ok3 && t.end == 10
    }())
    check("TrimRange starts as the full file", TrimRange(duration: 12).isFull)

    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    check("EditorNaming never overwrites an existing copy", {
        let src = dir.appendingPathComponent("holiday.jpg")
        let first = EditorNaming.outputURL(for: src, in: dir)
        FileManager.default.createFile(atPath: first.path, contents: Data())
        let second = EditorNaming.outputURL(for: src, in: dir)
        FileManager.default.createFile(atPath: second.path, contents: Data())
        let third = EditorNaming.outputURL(for: src, in: dir)
        return first.lastPathComponent == "holiday edited.jpg" && second.lastPathComponent == "holiday edited 2.jpg" && third.lastPathComponent == "holiday edited 3.jpg"
    }())
    check("EditorNaming supports a different extension and suffix",
          EditorNaming.outputURL(for: dir.appendingPathComponent("clip.mov"), suffix: "trimmed", extension: "mp4", in: dir).lastPathComponent == "clip trimmed.mp4")
    check("Editors replace the sheet only for a single selected file", {
        EditorKind.kind(for: .cropImage, selectionCount: 1) == .photo
            && EditorKind.kind(for: .cropImage, selectionCount: 3) == nil
            && EditorKind.kind(for: .trimAudio, selectionCount: 1) == .audio
            && EditorKind.kind(for: .trimVideo, selectionCount: 1) == .video
            && EditorKind.kind(for: .extractPagesPDF, selectionCount: 1) == .pdfPages
            && EditorKind.kind(for: .compressImage, selectionCount: 1) == nil
            && EditorKind.kind(for: .backgroundImage, selectionCount: 1) == .background
    }())

    print("\nEditors: photo pipeline")
    let quad = makeQuadrantImage()
    do {
        var e = PhotoEdits(); e.quarterTurns = 1
        let r = try PhotoPipeline.oriented(quad, edits: e)
        check("Rotating a quarter turn clockwise swaps dimensions and moves the corners",
              r.width == 100 && r.height == 200 && isColor(pixel(r, 5, 5), 0, 0, 255) && isColor(pixel(r, 95, 5), 255, 0, 0)
              && isColor(pixel(r, 95, 195), 0, 255, 0) && isColor(pixel(r, 5, 195), 255, 255, 0))
        e.quarterTurns = 2
        let r2 = try PhotoPipeline.oriented(quad, edits: e)
        check("Rotating 180 degrees puts yellow at the top left", r2.width == 200 && isColor(pixel(r2, 5, 5), 255, 255, 0))
        e.quarterTurns = 0; e.flipHorizontal = true
        let r3 = try PhotoPipeline.oriented(quad, edits: e)
        check("Horizontal flip mirrors left and right", isColor(pixel(r3, 5, 5), 0, 255, 0) && isColor(pixel(r3, 195, 5), 255, 0, 0))
        e.flipHorizontal = false; e.flipVertical = true
        let r4 = try PhotoPipeline.oriented(quad, edits: e)
        check("Vertical flip mirrors top and bottom", isColor(pixel(r4, 5, 5), 0, 0, 255) && isColor(pixel(r4, 5, 95), 255, 0, 0))
        check("orientedSize swaps for odd turns", { var x = PhotoEdits(); x.quarterTurns = 3; return x.orientedSize(of: CGSize(width: 200, height: 100)) == CGSize(width: 100, height: 200) }())

        var g = PhotoEdits(); g.grayscale = true
        let gray = try PhotoPipeline.adjusted(quad, edits: g)
        let gp = pixel(gray, 5, 5)
        check("Grayscale makes channels equal", abs(gp.r - gp.g) <= 2 && abs(gp.g - gp.b) <= 2 && gray.width == 200)
        var b = PhotoEdits(); b.brightness = 0.3
        let bright = try PhotoPipeline.adjusted(quad, edits: b)
        check("Brightness lifts a dark colour", pixel(bright, 5, 95).b == 255 && pixel(bright, 5, 95).r > 40)
        var s = PhotoEdits(); s.saturation = 0
        let desat = try PhotoPipeline.adjusted(quad, edits: s)
        check("Saturation 0 removes colour", abs(pixel(desat, 150, 5).r - pixel(desat, 150, 5).b) <= 2)
        let untouched = try PhotoPipeline.adjusted(quad, edits: PhotoEdits())
        check("No adjustments returns the identical image", untouched === quad)

        var full = PhotoEdits(); full.quarterTurns = 1; full.crop = CGRect(x: 0, y: 0, width: 100, height: 100); full.outputSize = CGSize(width: 40, height: 40)
        let rendered = try PhotoPipeline.render(quad, edits: full)
        check("render(): rotate, crop, resize in order", rendered.width == 40 && rendered.height == 40 && isColor(pixel(rendered, 3, 3), 0, 0, 255, tolerance: 40) && isColor(pixel(rendered, 36, 3), 255, 0, 0, tolerance: 40))
    } catch { check("photo pipeline threw: \(error)", false) }

    do {
        let src = try writeImage(quad, type: .png)
        let folder = src.deletingLastPathComponent()
        var e = PhotoEdits(); e.quarterTurns = 1; e.crop = CGRect(x: 10, y: 20, width: 60, height: 120); e.outputSize = CGSize(width: 30, height: 60)
        let result = try PhotoPipeline.export(source: src, edits: e, folder: folder)
        check("Export writes a new copy next to the original and keeps the original", result.outputURL.lastPathComponent == "photo edited.png" && FileManager.default.fileExists(atPath: src.path))
        check("Exported PNG has the requested size (verified with ImageIO)", imageSize(at: result.outputURL).map { $0 == (30, 60) } ?? false)
        let again = try PhotoPipeline.export(source: src, edits: e, folder: folder)
        check("A second export becomes 'edited 2'", again.outputURL.lastPathComponent == "photo edited 2.png")
        let jpg = try writeImage(quad, type: .jpeg)
        let jr = try PhotoPipeline.export(source: jpg, edits: { var x = PhotoEdits(); x.grayscale = true; return x }(), folder: jpg.deletingLastPathComponent())
        check("JPEG stays JPEG and keeps its size", ["jpg", "jpeg"].contains(jr.outputURL.pathExtension) && imageSize(at: jr.outputURL).map { $0 == (200, 100) } ?? false)
        check("pixelSize reads dimensions without decoding", PhotoPipeline.pixelSize(of: src) == CGSize(width: 200, height: 100))
    } catch { check("photo export threw: \(error)", false) }

    await run("Photo editor model: load, crop with preset, rotate resets crop, linked resize, export edits") {
        let src = try writeImage(makeQuadrantImage(width: 400, height: 300), type: .png)
        let model = try await PhotoEditorModel.load(src)
        guard model.originalSize == CGSize(width: 400, height: 300) else { throw TestFailure("size \(model.originalSize)") }
        guard !model.hasChanges else { throw TestFailure("fresh model should have no changes") }
        model.setAspect(.square)
        guard model.cropRect.width == model.cropRect.height, model.cropRect.width == 300 else { throw TestFailure("square crop \(model.cropRect)") }
        model.setCrop(width: 150)
        guard model.cropRect.width == 150, model.cropRect.height == 150 else { throw TestFailure("locked width edit \(model.cropRect)") }
        model.setResizeEnabled(true)
        model.setTargetWidth(75)
        guard model.targetHeight == 75 else { throw TestFailure("linked height \(model.targetHeight)") }
        let e = model.exportEdits
        guard e.crop == model.cropRect, e.outputSize == CGSize(width: 75, height: 75) else { throw TestFailure("export edits \(e)") }
        model.rotate(clockwise: true)
        guard model.orientedSize == CGSize(width: 300, height: 400), model.cropRect.width == model.cropRect.height else { throw TestFailure("after rotate \(model.orientedSize) \(model.cropRect)") }
        model.resetAll()
        guard !model.hasChanges else { throw TestFailure("reset should clear changes") }
        // simulated mouse drag on the canvas: grab the bottom-right corner
        model.setAspect(.free)
        model.setCrop(x: 0, y: 0, width: 200, height: 150)
        let display = CGRect(x: 0, y: 0, width: 400, height: 300)
        model.dragChanged(start: CGPoint(x: 200, y: 150), current: CGPoint(x: 260, y: 190), display: display)
        model.dragEnded()
        guard model.cropRect == CGRect(x: 0, y: 0, width: 260, height: 190) else { throw TestFailure("drag result \(model.cropRect)") }
    }
}

/// Fraction of pixels that differ from the first pixel — a cheap "something was drawn" check.
func nonBackgroundFraction(_ rep: NSBitmapImageRep) -> Double {
    guard let base = rep.colorAt(x: 2, y: 2) else { return 0 }
    var differing = 0, total = 0
    for y in stride(from: 0, to: rep.pixelsHigh, by: 6) {
        for x in stride(from: 0, to: rep.pixelsWide, by: 6) {
            total += 1
            guard let c = rep.colorAt(x: x, y: y) else { continue }
            if abs(c.redComponent - base.redComponent) + abs(c.greenComponent - base.greenComponent) + abs(c.blueComponent - base.blueComponent) > 0.05 { differing += 1 }
        }
    }
    return total == 0 ? 0 : Double(differing) / Double(total)
}

/// Saves a snapshot for human review when MANDARIN_SNAPSHOT_DIR is set.
func saveSnapshot(_ rep: NSBitmapImageRep, name: String) {
    guard let dir = ProcessInfo.processInfo.environment["MANDARIN_SNAPSHOT_DIR"],
          let data = rep.representation(using: .png, properties: [:]) else { return }
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    try? data.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
}

@MainActor
func runEditorSnapshotTests() async {
    print("\nEditors: offscreen rendering")
    await run("Photo editor view lays out and draws") {
        let src = try writeImage(makeQuadrantImage(width: 600, height: 400), type: .png)
        let model = try await PhotoEditorModel.load(src)
        model.setAspect(.r16x9)
        guard let rep = EditorSnapshots.photoEditor(model) else { throw TestFailure("no snapshot") }
        saveSnapshot(rep, name: "photo-editor")
        guard nonBackgroundFraction(rep) > 0.15 else { throw TestFailure("view looks blank") }
    }
}

// MARK: - PDF pages

/// A PDF whose page i is (width0 + 10*i) points wide, so order can be read back from page sizes.
func makeSizedPDF(pages: Int, width0: Int = 200, name: String = "pages.pdf") throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent(name)
    var first = CGRect(x: 0, y: 0, width: width0, height: 300)
    guard let context = CGContext(url as CFURL, mediaBox: &first, nil) else { throw TestFailure("no pdf context") }
    for i in 0..<pages {
        var box = CGRect(x: 0, y: 0, width: width0 + 10 * i, height: 300)
        context.beginPDFPage([kCGPDFContextMediaBox as String: NSData(bytes: &box, length: MemoryLayout<CGRect>.size)] as CFDictionary)
        context.setFillColor(CGColor(red: 0.2, green: 0.4 + CGFloat(i) * 0.05, blue: 0.8, alpha: 1))
        context.fill(box.insetBy(dx: 20, dy: 20))
        context.endPDFPage()
    }
    context.closePDF()
    return url
}

func pageWidths(_ url: URL) -> [Int] {
    guard let doc = PDFDocument(url: url) else { return [] }
    return (0..<doc.pageCount).compactMap { doc.page(at: $0).map { Int($0.bounds(for: .mediaBox).width) } }
}

@MainActor
func runPDFPageTests() async {
    print("\nEditors: PDF page tool")
    func ids(_ list: PDFPageList, _ positions: Int...) -> Set<UUID> { Set(positions.map { list.items[$0].id }) }
    func order(_ list: PDFPageList) -> [Int] { list.items.map(\.pageIndex) }

    var list = PDFPageList(documentIndex: 0, pageCount: 6)
    check("A new list is in source order", order(list) == [0, 1, 2, 3, 4, 5])
    list.move(ids(list, 4), toOffset: 1)
    check("Moving a page earlier", order(list) == [0, 4, 1, 2, 3, 5])
    list = PDFPageList(documentIndex: 0, pageCount: 6)
    list.move(ids(list, 1), toOffset: 4)
    check("Moving a page later lands before the target", order(list) == [0, 2, 3, 1, 4, 5])
    list = PDFPageList(documentIndex: 0, pageCount: 6)
    list.move(ids(list, 0, 1), toOffset: 6)
    check("Moving two pages to the end keeps their order", order(list) == [2, 3, 4, 5, 0, 1])
    list = PDFPageList(documentIndex: 0, pageCount: 6)
    list.move(ids(list, 1, 4), toOffset: 3)
    check("Moving a non-contiguous selection groups it at the target", order(list) == [0, 2, 1, 4, 3, 5])
    list = PDFPageList(documentIndex: 0, pageCount: 4)
    list.move(ids(list, 2), toOffset: 2)
    check("Dropping a page onto itself changes nothing", order(list) == [0, 1, 2, 3])
    list.shift(ids(list, 0), by: -1)
    check("Shifting the first page earlier is a no-op", order(list) == [0, 1, 2, 3])
    list.shift(ids(list, 1), by: 1)
    check("Shift later swaps with the next page", order(list) == [0, 2, 1, 3])
    list.shift(ids(list, 3), by: 1)
    check("Shifting the last page later is a no-op", order(list) == [0, 2, 1, 3])
    list.delete(ids(list, 0, 3))
    check("Delete removes exactly the selection", order(list) == [2, 1])
    list.rotate(ids(list, 0), by: 90); list.rotate(ids(list, 0), by: 270); list.rotate(ids(list, 1), by: -90)
    check("Rotation wraps modulo 360, also for negative turns", list.items[0].rotation == 0 && list.items[1].rotation == 270)
    list.append(documentIndex: 1, pageCount: 2)
    check("Appending a second document adds its pages at the end", list.items.count == 4 && list.items[3].documentIndex == 1 && list.items[3].pageIndex == 1)

    do {
        let a = try makeSizedPDF(pages: 5, width0: 200, name: "a.pdf")
        let b = try makeSizedPDF(pages: 2, width0: 400, name: "b.pdf")
        check("Fixture PDF has the expected page sizes", pageWidths(a) == [200, 210, 220, 230, 240])

        var l = PDFPageList(documentIndex: 0, pageCount: 5)
        l.move(ids(l, 4), toOffset: 0)                 // 240 first
        l.delete(ids(l, 2))                            // drop page 1 (210)
        l.append(documentIndex: 1, pageCount: 2)       // + 400, 410
        l.rotate(ids(l, 0), by: 90)
        let out = a.deletingLastPathComponent().appendingPathComponent("out.pdf")
        let result = try PDFPageBuilder.export(l.items, sources: [a, b], to: out)
        let built = PDFDocument(url: result.outputURL)
        check("Exported PDF has the new order, without deleted pages, plus the appended file (checked with PDFKit)",
              pageWidths(out) == [240, 200, 220, 230, 400, 410] || pageWidths(out) == [300, 200, 220, 230, 400, 410])
        check("Rotation is stored on the exported page", built?.page(at: 0)?.rotation == 90)
        check("The original file is untouched", pageWidths(a) == [200, 210, 220, 230, 240])
        let extract = try PDFPageBuilder.export(l.subset(ids(l, 1, 2)), sources: [a, b], to: a.deletingLastPathComponent().appendingPathComponent("x.pdf"))
        check("Extracting selected pages keeps just those, in order", pageWidths(extract.outputURL) == [200, 220])
        var threw = false
        do { _ = try PDFPageBuilder.build([], from: []) } catch { threw = true }
        check("Saving zero pages is an error, not an empty file", threw)

        await run("PDF pages model: load, select, reorder, delete, add PDF, drop, thumbnails") {
            let model = try await PDFPagesModel.load(a)
            guard model.list.items.count == 5, !model.hasChanges else { throw TestFailure("fresh model") }
            let first = model.list.items[0].id, third = model.list.items[2].id, last = model.list.items[4].id
            model.select(first, extend: false, range: false)
            model.select(third, extend: false, range: true)
            guard model.selection.count == 3 else { throw TestFailure("shift-range selection \(model.selection.count)") }
            model.select(first, extend: true, range: false)
            guard model.selection.count == 2 else { throw TestFailure("cmd-click toggle") }
            model.drop(last, before: first)
            guard model.list.items[0].id == last, model.hasChanges else { throw TestFailure("drop before") }
            model.selection = [model.list.items[1].id]
            model.rotateSelected(by: 90)
            model.deleteSelected()
            guard model.list.items.count == 4, model.selection.isEmpty else { throw TestFailure("delete") }
            await model.addPDF(b)
            guard model.list.items.count == 6, model.sources.count == 2 else { throw TestFailure("add pdf") }
            await model.addPDF(URL(fileURLWithPath: "/nonexistent.pdf"))
            guard model.errorMessage != nil, model.list.items.count == 6 else { throw TestFailure("bad pdf should report an error") }
            model.requestThumbnail(for: model.list.items[0])
            for _ in 0..<40 where model.thumbnail(for: model.list.items[0]) == nil { try await Task.sleep(nanoseconds: 50_000_000) }
            guard model.thumbnail(for: model.list.items[0]) != nil else { throw TestFailure("thumbnail never arrived") }
            if let rep = EditorSnapshots.pdfPages(model) {
                saveSnapshot(rep, name: "pdf-pages")
                guard nonBackgroundFraction(rep) > 0.03 else { throw TestFailure("pdf view looks blank") }
            }
        }
    } catch { check("pdf page tests threw: \(error)", false) }
}

// MARK: - Background tool

/// White canvas with a red ring (white hole inside) in the middle.
func makeRingImage(size: Int = 100) -> CGImage {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 25, y: 25, width: 50, height: 50))
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 40, y: 40, width: 20, height: 20))
    return context.makeImage()!
}

func makeTransparentImage(size: Int = 60) -> CGImage {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 25, y: 25, width: 10, height: 10))
    return context.makeImage()!
}

@MainActor
func runBackgroundTests() async {
    print("\nEditors: background tool")
    do {
        let ring = makeRingImage()
        let guessed = try BackgroundTool.guessBackgroundColor(ring)
        check("Corner sampling finds the white background", guessed.r > 0.98 && guessed.g > 0.98 && guessed.b > 0.98)
        check("Colour picking reads the pixel under a point", {
            guard let c = BackgroundTool.color(at: CGPoint(x: 30, y: 30), in: ring) else { return false }
            return c.r > 0.95 && c.g < 0.05 && c.b < 0.05
        }())

        let cut = try BackgroundTool.removeSolidColor(ring, key: .white, tolerance: 0.1, contiguous: true)
        check("Solid removal clears the outside, keeps the subject", pixel(cut, 2, 2).a == 0 && pixel(cut, 97, 97).a == 0 && pixel(cut, 30, 30).a == 255)
        check("Contiguous mode keeps an enclosed hole of the same colour", pixel(cut, 50, 50).a == 255)
        let all = try BackgroundTool.removeSolidColor(ring, key: .white, tolerance: 0.1, contiguous: false)
        check("Non-contiguous mode also clears the enclosed hole", pixel(all, 50, 50).a == 0 && pixel(all, 30, 30).a == 255)
        let none = try BackgroundTool.removeSolidColor(ring, key: .white, tolerance: 0, contiguous: true)
        check("Tolerance 0 still removes exact matches", pixel(none, 2, 2).a == 0)
        let wide = try BackgroundTool.removeSolidColor(ring, key: .white, tolerance: 0.9, contiguous: true)
        check("A very large tolerance eats into the subject", pixel(wide, 30, 30).a < 255)
        let near = try BackgroundTool.removeSolidColor(ring, key: RGB(r: 1, g: 0.97, b: 0.97), tolerance: 0.1, contiguous: true)
        check("A slightly different key colour within tolerance still works", pixel(near, 2, 2).a == 0)

        let t = makeTransparentImage()
        let solid = try BackgroundTool.composite(t, fill: .solid(RGB(r: 0, g: 0, b: 1)))
        check("Solid fill goes behind transparency and keeps the subject on top", isColor(pixel(solid, 2, 2), 0, 0, 255) && pixel(solid, 2, 2).a == 255 && isColor(pixel(solid, 30, 30), 255, 0, 0))
        let grad = try BackgroundTool.composite(t, fill: .gradient(from: RGB(r: 0, g: 0, b: 0), to: .white, angleDegrees: 0))
        check("Gradient at 0 degrees runs left (first colour) to right (second)", pixel(grad, 1, 3).r < 30 && pixel(grad, 58, 3).r > 225)
        let down = try BackgroundTool.composite(t, fill: .gradient(from: RGB(r: 0, g: 0, b: 0), to: .white, angleDegrees: 90))
        check("Gradient at 90 degrees runs top to bottom", pixel(down, 3, 1).r < 30 && pixel(down, 3, 58).r > 225)
        let unchanged = try BackgroundTool.composite(t, fill: .none)
        check("Fill .none returns the image unchanged", unchanged === t)

        let src = try writeImage(ring, type: .png, name: "logo.png")
        let result = try BackgroundTool.export(source: src, edit: BackgroundEdit(removal: .solidColor(key: .white, tolerance: 0.1, contiguous: true), fill: .none), folder: src.deletingLastPathComponent())
        let source = CGImageSourceCreateWithURL(result.outputURL as CFURL, nil)
        let props = source.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
        check("Export is a PNG copy named '... background.png' with an alpha channel (ImageIO)",
              result.outputURL.lastPathComponent == "logo background.png" && (props?[kCGImagePropertyHasAlpha] as? Bool) == true
              && imageSize(at: result.outputURL).map { $0 == (100, 100) } ?? false)
        let out = try PhotoPipeline.decode(result.outputURL)
        check("Exported pixels are transparent outside and opaque inside", pixel(out, 2, 2).a == 0 && pixel(out, 30, 30).a == 255)

        if BackgroundTool.subjectMaskAvailable {
            do {
                let cutout = try BackgroundTool.removeSubject(ring)
                skip("Vision foreground mask on a synthetic image", because: cutout == nil ? "no subject detected in the synthetic fixture, which is acceptable" : "ran; result checked for size only")
                if let cutout { check("Vision cutout keeps the image size", cutout.width == 100 && cutout.height == 100) }
            } catch {
                skip("Vision foreground mask", because: "Vision failed in this environment: \(error.localizedDescription)")
            }
        } else {
            skip("Vision foreground mask", because: "needs macOS 14+")
        }

        await run("Background editor model: edits, key picking and preview") {
            let model = try await BackgroundEditorModel.load(src)
            guard !model.hasChanges || model.edit.fill != .none else { throw TestFailure("state") }
            model.fillMode = .none
            guard !model.hasChanges else { throw TestFailure("fresh model with no fill should have no changes") }
            model.removalMode = .solid
            model.pickKey(atFraction: CGPoint(x: 0.3, y: 0.3))
            guard model.keyColor.r > 0.95, model.keyColor.g < 0.1 else { throw TestFailure("picked colour \(model.keyColor)") }
            model.pickKey(atFraction: CGPoint(x: 0.01, y: 0.01))
            model.fillMode = .gradient
            guard case .solidColor = model.edit.removal, case .gradient = model.edit.fill, model.hasChanges else { throw TestFailure("edit \(model.edit)") }
            for _ in 0..<60 where model.working || model.preview.size.width == 0 { try await Task.sleep(nanoseconds: 50_000_000) }
            try await Task.sleep(nanoseconds: 400_000_000)
            if let rep = EditorSnapshots.backgroundEditor(model) {
                saveSnapshot(rep, name: "background-editor")
                guard nonBackgroundFraction(rep) > 0.03 else { throw TestFailure("view looks blank") }
            }
        }
    } catch { check("background tests threw: \(error)", false) }
}

// MARK: - Audio editor

/// 4 s mono audio at 8 kHz: silence for 2 s, then a 0.8-amplitude 440 Hz tone for 2 s.
func makeSilenceThenTone(ext: String = "wav") throws -> URL {
    guard let ffmpeg = ExternalTool.ffmpeg.path else { throw TestFailure("ffmpeg missing") }
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("tone.\(ext)")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: ffmpeg)
    process.standardInput = FileHandle.nullDevice
    process.arguments = ["-nostdin", "-y", "-f", "lavfi", "-i", "aevalsrc=if(lt(t\\,2)\\,0\\,0.8*sin(2*PI*440*t)):d=4:s=8000", "-loglevel", "error", url.path]
    process.standardError = FileHandle.nullDevice
    try process.run(); process.waitUntilExit()
    guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: url.path) else { throw TestFailure("couldn't make \(ext) fixture") }
    return url
}

@MainActor
func runAudioTests() async {
    print("\nEditors: audio editor")

    check("PeakAccumulator buckets samples by position", {
        var acc = PeakAccumulator(bucketCount: 4, totalFrames: 8)
        acc.add([0.1, -0.5, 0.2, 0.2, 0, 0, -1, 0.3])
        return acc.peaks == [0.5, 0.2, 0, 1] && acc.framesSeen == 8
    }())
    check("PeakAccumulator gives the same result however the stream is chunked", {
        let samples: [Float] = (0..<1000).map { sin(Float($0) / 7) }
        var whole = PeakAccumulator(bucketCount: 50, totalFrames: 1000)
        whole.add(samples)
        var chunked = PeakAccumulator(bucketCount: 50, totalFrames: 1000)
        var i = 0
        for size in [1, 7, 100, 3, 400, 489] { chunked.add(Array(samples[i..<min(i + size, 1000)])); i += size }
        return whole.peaks == chunked.peaks
    }())
    check("PeakAccumulator survives more samples than announced (clamps to the last bucket)", {
        var acc = PeakAccumulator(bucketCount: 3, totalFrames: 3)
        acc.add([0.1, 0.1, 0.1, 0.9, 0.9])
        return acc.peaks.count == 3 && acc.peaks[2] == 0.9
    }())

    let plan = AudioTrimPlan(start: 1, end: 3, fadeIn: 0.5, fadeOut: 0.5, volume: 0.5)
    let args = plan.ffmpegArguments(input: URL(fileURLWithPath: "/in.wav"), output: URL(fileURLWithPath: "/out.wav"))
    check("Trim plan builds the expected ffmpeg arguments",
          args.contains("-ss") && args[args.firstIndex(of: "-ss")! + 1] == "1.000" && args[args.firstIndex(of: "-t")! + 1] == "2.000"
          && (args[args.firstIndex(of: "-af")! + 1] == "afade=t=in:st=0:d=0.500,afade=t=out:st=1.500:d=0.500,volume=0.500"))
    check("Overlapping fades are scaled down to fit the selection", {
        let p = AudioTrimPlan(start: 0, end: 2, fadeIn: 3, fadeOut: 1)
        let f = p.effectiveFades
        return abs(f.in + f.out - 2) < 1e-9 && abs(f.in / f.out - 3) < 1e-9
    }())
    check("A plan without edits has no filters; mp3/m4a pick sensible codecs", {
        let p = AudioTrimPlan(start: 0, end: 5)
        let mp3 = p.ffmpegArguments(input: URL(fileURLWithPath: "/a.mp3"), output: URL(fileURLWithPath: "/b.mp3"))
        let m4a = p.ffmpegArguments(input: URL(fileURLWithPath: "/a.m4a"), output: URL(fileURLWithPath: "/b.m4a"))
        return !mp3.contains("-af") && mp3.contains("libmp3lame") && m4a.contains("aac")
    }())
    check("Split divides at the playhead and keeps the fades on the outer ends", {
        guard let (a, b) = AudioTrimPlan(start: 1, end: 9, fadeIn: 1, fadeOut: 2, volume: 1.5).split(at: 4) else { return false }
        return a.start == 1 && a.end == 4 && a.fadeIn == 1 && a.fadeOut == 0 && b.start == 4 && b.end == 9 && b.fadeIn == 0 && b.fadeOut == 2 && b.volume == 1.5
    }())
    check("Split refuses a playhead outside or on the edge of the selection",
          AudioTrimPlan(start: 1, end: 9).split(at: 1) == nil && AudioTrimPlan(start: 1, end: 9).split(at: 0.2) == nil && AudioTrimPlan(start: 1, end: 9).split(at: 9.5) == nil)

    guard ExternalTool.ffmpeg.isAvailable else { skip("audio editor fixtures", because: "ffmpeg not installed"); return }
    do {
        let wav = try makeSilenceThenTone()
        let peaks = try await WaveformLoader.load(wav, bucketCount: 40)
        check("Waveform of a WAV (AVAudioFile path): silent first half, loud second half",
              peaks.count == 40 && peaks[..<18].allSatisfy { $0 < 0.05 } && peaks[22...].allSatisfy { $0 > 0.6 && $0 < 0.9 })
        let ogg = try makeSilenceThenTone(ext: "ogg")
        let oggPeaks = try await WaveformLoader.load(ogg, bucketCount: 40)
        check("Waveform of an OGG (ffmpeg streaming path) matches", oggPeaks.count == 40 && oggPeaks[..<18].allSatisfy { $0 < 0.1 } && oggPeaks[22...].allSatisfy { $0 > 0.5 })

        let task = Task { try await WaveformLoader.load(wav, bucketCount: 40) }
        task.cancel()
        var cancelled = false
        do { _ = try await task.value } catch is CancellationError { cancelled = true } catch {}
        check("Waveform loading honours cancellation", cancelled)

        let folder = wav.deletingLastPathComponent()
        let out = EditorNaming.outputURL(for: wav, suffix: "trimmed", in: folder)
        _ = try await AudioExport.export(source: wav, plan: AudioTrimPlan(start: 1, end: 3, fadeIn: 0, fadeOut: 1, volume: 0.5), output: out, progress: { _ in })
        let duration = FileToolMediaArgs.probeDuration(of: out) ?? 0
        check("Trimmed export has the selected length (ffprobe)", abs(duration - 2.0) < 0.08)
        let outPeaks = try await WaveformLoader.load(out, bucketCount: 20)
        check("Volume 50% halves the level and fade-out brings the end to silence", outPeaks[11] > 0.3 && outPeaks[11] < 0.45 && outPeaks[19] < 0.15)
        check("The original file is untouched", abs((FileToolMediaArgs.probeDuration(of: wav) ?? 0) - 4.0) < 0.05)

        let mp3Source = folder.appendingPathComponent("tone.mp3")
        _ = try await AudioExport.export(source: wav, plan: AudioTrimPlan(start: 0, end: 4), output: mp3Source, progress: { _ in })
        let mp3Out = EditorNaming.outputURL(for: mp3Source, suffix: "trimmed", in: folder)
        _ = try await AudioExport.export(source: mp3Source, plan: AudioTrimPlan(start: 0.5, end: 2.5), output: mp3Out, progress: { _ in })
        check("MP3 trim stays an MP3 of about the right length", mp3Out.pathExtension == "mp3" && abs((FileToolMediaArgs.probeDuration(of: mp3Out) ?? 0) - 2.0) < 0.15)

        var failed = false
        do { _ = try await AudioExport.export(source: wav, plan: AudioTrimPlan(start: 2, end: 2), output: folder.appendingPathComponent("empty.wav"), progress: { _ in }) } catch { failed = true }
        check("An empty selection is refused with an error", failed)

        await run("Audio editor model: load, trim, fades clamp, split availability, waveform, snapshot") {
            let model = try await AudioEditorModel.load(wav)
            guard abs(model.duration - 4) < 0.05, !model.hasChanges else { throw TestFailure("fresh model") }
            model.setStart(1); model.setEnd(3)
            guard model.trim.start == 1, model.trim.end == 3, model.hasChanges else { throw TestFailure("trim") }
            model.fadeIn = 1.5
            model.setEnd(1.5)
            guard model.fadeIn <= 0.5 + 1e-9 else { throw TestFailure("fade should clamp to the selection, got \(model.fadeIn)") }
            guard !model.canSplit else { throw TestFailure("playhead at 0 is outside the selection") }
            for _ in 0..<60 where model.waveformLoading { try await Task.sleep(nanoseconds: 50_000_000) }
            guard model.peaks.count == AudioEditorModel.bucketCount else { throw TestFailure("peaks \(model.peaks.count)") }
            model.setEnd(3)
            if let rep = EditorSnapshots.audioEditor(model) {
                saveSnapshot(rep, name: "audio-editor")
                guard nonBackgroundFraction(rep) > 0.03 else { throw TestFailure("view looks blank") }
            }
            model.cancelWork()
        }
    } catch { check("audio tests threw: \(error)", false) }
}

// MARK: - Video trimmer

/// 6 s, 320x240, 30 fps, a keyframe every second so stream-copy cuts land exactly.
func makeKeyframedVideo(ext: String = "mp4") throws -> URL {
    guard let ffmpeg = ExternalTool.ffmpeg.path else { throw TestFailure("ffmpeg missing") }
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("clip.\(ext)")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: ffmpeg)
    let video = ext == "webm" ? ["-c:v", "libvpx-vp9", "-g", "30"] : ["-c:v", "libx264", "-g", "30", "-keyint_min", "30", "-sc_threshold", "0", "-pix_fmt", "yuv420p"]
    let audio = ext == "webm" ? ["-c:a", "libopus"] : ["-c:a", "aac"]
    process.standardInput = FileHandle.nullDevice
    process.arguments = ["-nostdin", "-y", "-f", "lavfi", "-i", "testsrc=duration=6:size=320x240:rate=30", "-f", "lavfi", "-i", "sine=frequency=440:duration=6"]
        + video + audio + ["-shortest", "-loglevel", "error", url.path]
    process.standardError = FileHandle.nullDevice
    try process.run(); process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw TestFailure("couldn't make \(ext) video fixture") }
    return url
}

func videoDimensions(_ url: URL) -> (Int, Int)? {
    guard let ffprobe = ExternalTool.ffprobe.path else { return nil }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: ffprobe)
    process.standardInput = FileHandle.nullDevice
    process.arguments = ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height", "-of", "csv=p=0:s=x", url.path]
    let pipe = Pipe()
    process.standardOutput = pipe
    guard (try? process.run()) != nil else { return nil }
    process.waitUntilExit()
    let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let parts = text.split(separator: "x").compactMap { Int($0) }
    return parts.count == 2 ? (parts[0], parts[1]) : nil
}

@MainActor
func runVideoTests() async {
    print("\nEditors: video trimmer")

    check("Lossless plan uses stream copy and drops nothing but extra streams", {
        let plan = VideoTrimPlan(start: 2, end: 5)
        let args = plan.ffmpegArguments(input: URL(fileURLWithPath: "/in.mp4"), output: URL(fileURLWithPath: "/out.mp4"))
        return plan.isLossless && args.contains("copy") && !args.contains("-vf") && args[args.firstIndex(of: "-ss")! + 1] == "2.000" && args[args.firstIndex(of: "-t")! + 1] == "3.000"
    }())
    check("A crop forces re-encoding even when fast cut is requested", {
        let plan = VideoTrimPlan(start: 0, end: 4, crop: CGRect(x: 11, y: 7, width: 101, height: 55), fastCut: true)
        let args = plan.ffmpegArguments(input: URL(fileURLWithPath: "/in.mp4"), output: URL(fileURLWithPath: "/out.mp4"))
        return !plan.isLossless && !args.contains("copy") && args.contains("libx264") && args[args.firstIndex(of: "-vf")! + 1] == "crop=100:54:10:6"
    }())
    check("Exact mode without a crop re-encodes and WebM gets VP9/Opus", {
        let exact = VideoTrimPlan(start: 0, end: 4, fastCut: false)
        let a = exact.ffmpegArguments(input: URL(fileURLWithPath: "/in.mp4"), output: URL(fileURLWithPath: "/out.webm"))
        return !exact.isLossless && a.contains("libvpx-vp9") && a.contains("libopus") && !a.contains("copy")
    }())
    check("evenCrop never produces odd or zero sizes", {
        let c = VideoTrimPlan.evenCrop(CGRect(x: 1, y: 3, width: 1, height: 5))
        return c.w == 2 && c.h == 4 && c.x == 0 && c.y == 2
    }())

    guard ExternalTool.ffmpeg.isAvailable, ExternalTool.ffprobe.isAvailable else { skip("video fixtures", because: "ffmpeg/ffprobe not installed"); return }
    do {
        let video = try makeKeyframedVideo()
        let folder = video.deletingLastPathComponent()
        let info = try await VideoInfo.probe(video)
        check("VideoInfo reads duration and size", abs(info.duration - 6) < 0.2 && info.size == CGSize(width: 320, height: 240))
        let webm = try makeKeyframedVideo(ext: "webm")
        let webmInfo = try await VideoInfo.probe(webm)
        check("VideoInfo falls back to ffprobe for WebM", abs(webmInfo.duration - 6) < 0.3 && webmInfo.size == CGSize(width: 320, height: 240))

        let fast = EditorNaming.outputURL(for: video, suffix: "trimmed", in: folder)
        let fastResult = try await VideoExport.export(source: video, plan: VideoTrimPlan(start: 2, end: 5), output: fast, progress: { _ in })
        let fastDuration = FileToolMediaArgs.probeDuration(of: fast) ?? 0
        check("Fast cut: right length (ffprobe), same size, no re-encode warning missing", abs(fastDuration - 3.0) < 0.25 && videoDimensions(fast).map { $0 == (320, 240) } == true && fastResult.warning != nil)

        let exact = EditorNaming.outputURL(for: video, suffix: "trimmed", in: folder)
        _ = try await VideoExport.export(source: video, plan: VideoTrimPlan(start: 1.5, end: 3.5, fastCut: false), output: exact, progress: { _ in })
        check("Exact cut lands on the requested length", abs((FileToolMediaArgs.probeDuration(of: exact) ?? 0) - 2.0) < 0.12)

        let cropped = EditorNaming.outputURL(for: video, suffix: "trimmed", in: folder)
        var reported = 0.0
        let box = CGRect(x: 40, y: 20, width: 160, height: 120)
        _ = try await VideoExport.export(source: video, plan: VideoTrimPlan(start: 0, end: 3, crop: box), output: cropped, progress: { reported = max(reported, $0) })
        check("Cropped export has the cropped size and length (ffprobe)", videoDimensions(cropped).map { $0 == (160, 120) } == true && abs((FileToolMediaArgs.probeDuration(of: cropped) ?? 0) - 3.0) < 0.15)
        check("Progress is reported up to 100%", reported >= 0.99)
        check("Original video is untouched", abs((FileToolMediaArgs.probeDuration(of: video) ?? 0) - 6) < 0.2 && videoDimensions(video).map { $0 == (320, 240) } == true)
        check("Output names never overwrite", fast != exact && exact != cropped && fast.deletingLastPathComponent() == folder)

        let webmOut = EditorNaming.outputURL(for: webm, suffix: "trimmed", in: folder)
        _ = try await VideoExport.export(source: webm, plan: VideoTrimPlan(start: 1, end: 4), output: webmOut, progress: { _ in })
        check("WebM can be trimmed without re-encoding", abs((FileToolMediaArgs.probeDuration(of: webmOut) ?? 0) - 3.0) < 0.3)

        // Cancellation: a long re-encode is cancelled and leaves no partial file.
        let cancelOut = EditorNaming.outputURL(for: video, suffix: "cancelled", in: folder)
        let task = Task { try await VideoExport.export(source: video, plan: VideoTrimPlan(start: 0, end: 6, fastCut: false), output: cancelOut, progress: { _ in }) }
        try await Task.sleep(nanoseconds: 80_000_000)
        task.cancel()
        var cancelled = false
        do { _ = try await task.value } catch is CancellationError { cancelled = true } catch { cancelled = false }
        // A very fast encode can finish before the cancel lands; that's fine as long as nothing is left half-written.
        check("Cancelling a video export stops it and removes partial output", cancelled ? !FileManager.default.fileExists(atPath: cancelOut.path) : (FileToolMediaArgs.probeDuration(of: cancelOut) ?? 0) > 5)

        var thumbs: [Int: NSImage] = [:]
        let box2 = ThumbnailBox()
        await ThumbnailStrip.generate(url: video, duration: info.duration, count: 6) { i, image in box2.set(i, image) }
        thumbs = box2.values
        check("Thumbnail strip delivers frames (AVFoundation)", thumbs.count == 6 && thumbs.values.allSatisfy { $0.size.width > 10 })
        let box3 = ThumbnailBox()
        await ThumbnailStrip.generate(url: webm, duration: webmInfo.duration, count: 4) { i, image in box3.set(i, image) }
        check("Thumbnail strip falls back to ffmpeg for WebM", box3.values.count == 4)

        await run("Video editor model: load, trim, crop box, fast-cut rules, snapshot") {
            let model = try await VideoEditorModel.load(video)
            guard model.info.size == CGSize(width: 320, height: 240), !model.hasChanges, model.plan.isLossless else { throw TestFailure("fresh model") }
            model.setStart(1); model.setEnd(4)
            guard model.plan.start == 1, model.plan.end == 4, model.hasChanges else { throw TestFailure("trim") }
            model.cropEnabled = true
            guard !model.fastCut, model.plan.crop == nil else { throw TestFailure("enabling crop should switch to exact cut; full-frame crop means no crop") }
            model.setAspect(.square)
            guard model.cropRect.width == model.cropRect.height, model.plan.crop != nil else { throw TestFailure("square crop \(model.cropRect)") }
            model.dragChanged(start: CGPoint(x: model.cropRect.midX, y: model.cropRect.midY), current: CGPoint(x: model.cropRect.midX - 10, y: model.cropRect.midY), display: CGRect(x: 0, y: 0, width: 320, height: 240))
            model.dragEnded()
            guard model.cropRect.minX == 30 else { throw TestFailure("body drag moved the box to \(model.cropRect)") }
            for _ in 0..<80 where model.thumbnails.count < VideoEditorModel.thumbnailCount { try await Task.sleep(nanoseconds: 50_000_000) }
            guard model.thumbnails.count == VideoEditorModel.thumbnailCount else { throw TestFailure("thumbnails \(model.thumbnails.count)") }
            if let rep = EditorSnapshots.videoEditor(model) {
                saveSnapshot(rep, name: "video-editor")
                guard nonBackgroundFraction(rep) > 0.03 else { throw TestFailure("view looks blank") }
            }
            model.cancelWork()
        }
    } catch { check("video tests threw: \(error)", false) }
}

final class ThumbnailBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Int: NSImage] = [:]
    func set(_ index: Int, _ image: NSImage) { lock.lock(); storage[index] = image; lock.unlock() }
    var values: [Int: NSImage] { lock.lock(); defer { lock.unlock() }; return storage }
}
