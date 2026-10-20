import UniformTypeIdentifiers

enum FileToolCategory {
    case image, video, audio, pdf, archive
}

/// The 27 File Tools. Each is gated to the file type(s) it actually
/// applies to — the Command wheel only ever shows tools relevant to
/// what's dragged. Merge tools additionally require 2+ files selected
/// (nothing to merge with just one); everything else works on a single
/// file, a folder, or a mixed selection (each item handled independently).
public enum FileTool: String, CaseIterable {
    // Image
    case compressImage, resizeImage, cropImage, rotateImage, flipImage, grayscaleImage, stripMetadataImage, backgroundImage
    // Video
    case compressVideo, resizeVideo, cropVideo, trimVideo, rotateVideo, changeSpeedVideo, extractAudio, mergeVideo, grayscaleVideo
    // Audio
    case trimAudio, changeSpeedAudio, mergeAudio
    // PDF
    case compressPDF, splitPDF, mergePDF, rotatePDF, extractPagesPDF, stripMetadataPDF
    // Archive
    case compressArchive

    public var title: String {
        switch self {
        case .compressImage, .compressVideo, .compressPDF: return "Compress"
        case .resizeImage, .resizeVideo: return "Resize"
        case .cropImage, .cropVideo: return "Crop"
        case .rotateImage, .rotateVideo, .rotatePDF: return "Rotate"
        case .flipImage: return "Flip"
        case .grayscaleImage, .grayscaleVideo: return "Grayscale"
        case .stripMetadataImage, .stripMetadataPDF: return "Strip Metadata"
        case .backgroundImage: return "Background"
        case .trimVideo, .trimAudio: return "Trim"
        case .changeSpeedVideo, .changeSpeedAudio: return "Change Speed"
        case .extractAudio: return "Extract Audio"
        case .mergeVideo, .mergeAudio, .mergePDF: return "Merge"
        case .splitPDF: return "Split"
        case .extractPagesPDF: return "Extract Pages"
        case .compressArchive: return "Compress"
        }
    }

    /// Category-qualified, for VoiceOver — "Compress" alone is ambiguous
    /// when a category's own Compress and the universal Compress Archive
    /// can appear in the same wheel together.
    public var accessibilityLabel: String {
        switch self {
        case .compressImage: return "Compress Image"
        case .resizeImage: return "Resize Image"
        case .cropImage: return "Crop Image"
        case .rotateImage: return "Rotate Image"
        case .flipImage: return "Flip Image"
        case .grayscaleImage: return "Grayscale Image"
        case .stripMetadataImage: return "Strip Image Metadata"
        case .backgroundImage: return "Edit Image Background"
        case .compressVideo: return "Compress Video"
        case .resizeVideo: return "Resize Video"
        case .cropVideo: return "Crop Video"
        case .trimVideo: return "Trim Video"
        case .rotateVideo: return "Rotate Video"
        case .changeSpeedVideo: return "Change Video Speed"
        case .extractAudio: return "Extract Audio from Video"
        case .mergeVideo: return "Merge Videos"
        case .grayscaleVideo: return "Grayscale Video"
        case .trimAudio: return "Trim Audio"
        case .changeSpeedAudio: return "Change Audio Speed"
        case .mergeAudio: return "Merge Audio Files"
        case .compressPDF: return "Compress PDF"
        case .splitPDF: return "Split PDF"
        case .mergePDF: return "Merge PDFs"
        case .rotatePDF: return "Rotate PDF Pages"
        case .extractPagesPDF: return "Extract PDF Pages"
        case .stripMetadataPDF: return "Strip PDF Metadata"
        case .compressArchive: return "Compress Archive"
        }
    }

    public var icon: String {
        switch self {
        case .compressImage, .compressVideo, .compressPDF, .compressArchive: return "arrow.down.right.and.arrow.up.left"
        case .resizeImage, .resizeVideo: return "arrow.up.left.and.arrow.down.right"
        case .cropImage, .cropVideo: return "crop"
        case .rotateImage, .rotateVideo, .rotatePDF: return "rotate.right"
        case .flipImage: return "arrow.left.and.right.righttriangle.left.righttriangle.right"
        case .grayscaleImage, .grayscaleVideo: return "circle.lefthalf.filled"
        case .stripMetadataImage, .stripMetadataPDF: return "eye.slash"
        case .backgroundImage: return "photo.on.rectangle"
        case .trimVideo, .trimAudio: return "scissors"
        case .changeSpeedVideo, .changeSpeedAudio: return "speedometer"
        case .extractAudio: return "waveform"
        case .mergeVideo, .mergeAudio, .mergePDF: return "rectangle.stack"
        case .splitPDF: return "square.split.2x1"
        case .extractPagesPDF: return "doc.on.doc"
        }
    }

    var category: FileToolCategory {
        switch self {
        case .compressImage, .resizeImage, .cropImage, .rotateImage, .flipImage, .grayscaleImage, .stripMetadataImage, .backgroundImage:
            return .image
        case .compressVideo, .resizeVideo, .cropVideo, .trimVideo, .rotateVideo, .changeSpeedVideo, .extractAudio, .mergeVideo, .grayscaleVideo:
            return .video
        case .trimAudio, .changeSpeedAudio, .mergeAudio:
            return .audio
        case .compressPDF, .splitPDF, .mergePDF, .rotatePDF, .extractPagesPDF, .stripMetadataPDF:
            return .pdf
        case .compressArchive:
            return .archive
        }
    }

    /// Tools spanning a multi-file selection (combine N files into one) —
    /// meaningless for a single file.
    var requiresMultipleFiles: Bool {
        switch self {
        case .mergeVideo, .mergeAudio, .mergePDF: return true
        default: return false
        }
    }

    /// Editor-only tools: no numeric fallback, so they need exactly one file.
    var requiresSingleFile: Bool { self == .backgroundImage }

    public var parameters: [ToolParameter] {
        switch self {
        case .resizeImage, .resizeVideo:
            return [.number(key: "width", label: "Width", defaultValue: 1280, range: 1...10000),
                    .number(key: "height", label: "Height", defaultValue: 720, range: 1...10000)]
        case .cropImage, .cropVideo:
            return [.number(key: "x", label: "X", defaultValue: 0, range: 0...100000),
                    .number(key: "y", label: "Y", defaultValue: 0, range: 0...100000),
                    .number(key: "width", label: "Width", defaultValue: 100, range: 1...100000),
                    .number(key: "height", label: "Height", defaultValue: 100, range: 1...100000)]
        case .rotateImage, .rotateVideo, .rotatePDF:
            return [.number(key: "degrees", label: "Degrees", defaultValue: 90, range: -360...360)]
        case .flipImage:
            return [.picker(key: "axis", label: "Direction", options: ["Horizontal", "Vertical"], defaultValue: "Horizontal")]
        case .trimVideo, .trimAudio:
            return [.number(key: "start", label: "Start (seconds)", defaultValue: 0, range: 0...100000),
                    .number(key: "end", label: "End (seconds)", defaultValue: 10, range: 0...100000)]
        case .changeSpeedVideo, .changeSpeedAudio:
            return [.number(key: "speed", label: "Speed (0.5-2.0×)", defaultValue: 1.0, range: 0.5...2.0)]
        case .compressImage:
            return [.number(key: "quality", label: "Quality (0.1-1.0)", defaultValue: 0.5, range: 0.1...1.0)]
        case .extractPagesPDF:
            return [.text(key: "pages", label: "Pages (e.g. 1-3,5)", defaultValue: "1")]
        default:
            return []
        }
    }

    public static func tools(for type: UTType, selectionCount: Int) -> [FileTool] {
        let category: FileToolCategory?
        // PDF checked first: `ImageFormats` lists `.pdf` as an *export
        // target* for images (so Convert can offer "PDF" from a photo),
        // which would otherwise make `ImageFormats.format(for: .pdf)`
        // non-nil and misclassify a dragged PDF itself as an image here.
        // GIF is checked before plain image-conformance for a similar
        // reason: it conforms to `public.image` but is classified as
        // `.video` throughout this app (see `MediaFormats`).
        if type == .pdf {
            category = .pdf
        } else if let mediaFormat = MediaFormats.format(for: type) {
            category = mediaFormat.domain == .video ? .video : .audio
        } else if ImageFormats.format(for: type) != nil || type.conforms(to: .image) {
            category = .image
        } else {
            category = nil
        }

        var tools = allCases.filter { tool in
            guard let category else { return false }
            guard tool.category == category else { return false }
            if tool.requiresSingleFile { return selectionCount == 1 }
            if tool.requiresMultipleFiles { return selectionCount > 1 }
            return true
        }
        // Compress (archive) is universal — this is the "zip any file" tool
        // the Convert wheel deliberately doesn't offer, to keep it from
        // appearing on every single format's wheel there.
        tools.append(.compressArchive)
        return tools
    }
}

public enum ToolParameter {
    case number(key: String, label: String, defaultValue: Double, range: ClosedRange<Double>)
    case text(key: String, label: String, defaultValue: String)
    case picker(key: String, label: String, options: [String], defaultValue: String)
}
