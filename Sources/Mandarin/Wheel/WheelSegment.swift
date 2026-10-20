import Foundation
import UniformTypeIdentifiers

public struct WheelSegment: Identifiable {
    public let id: String
    let title: String
    let systemImage: String

    /// Set for `.convert` segments built from the registry.
    public let outputType: UTType?
    /// Set for `.fileActions` segments.
    let fileAction: FileAction?
    /// Set for `.fileTools` segments.
    let fileTool: FileTool?

    init(id: String, title: String, systemImage: String, outputType: UTType? = nil, fileAction: FileAction? = nil, fileTool: FileTool? = nil) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.outputType = outputType
        self.fileAction = fileAction
        self.fileTool = fileTool
    }

    /// What VoiceOver reads. Usually just `title`, except File Tools:
    /// "Compress" alone is ambiguous when, say, a video's own Compress
    /// sits next to the universal Compress Archive in the same wheel —
    /// same short visual label, but a reader needs the category to tell
    /// them apart.
    var accessibilityLabel: String {
        fileTool?.accessibilityLabel ?? title
    }

    /// The common Convert targets across every dragged file's type —
    /// each target must work for *all* of them, so a mixed selection never
    /// offers a format that would fail on one of the files.
    public static func convertSegments(for inputTypes: [UTType]) -> [WheelSegment] {
        guard let first = inputTypes.first else { return [] }
        var common = Set(ConverterRegistry.shared.availableTargets(for: first))
        for type in inputTypes.dropFirst() {
            common.formIntersection(ConverterRegistry.shared.availableTargets(for: type))
        }
        return ConverterRegistry.candidateOutputTypes.filter(common.contains).map { type in
            WheelSegment(
                id: type.identifier,
                title: FormatCatalog.fileExtension(for: type).uppercased(),
                systemImage: FormatCatalog.icon(for: type),
                outputType: type
            )
        }
    }

    static func fileActionSegments() -> [WheelSegment] {
        FileAction.allCases.map { action in
            WheelSegment(id: action.rawValue, title: action.title, systemImage: action.icon, fileAction: action)
        }
    }

    /// The union of tools applicable to any of the dragged files' types —
    /// a mixed selection (e.g. an image and a video together) shows both
    /// sets; running a tool only ever touches the files it actually
    /// applies to (see `FileToolRunner`).
    static func fileToolSegments(for inputTypes: [UTType], selectionCount: Int) -> [WheelSegment] {
        var seen: Set<FileTool> = []
        var tools: [FileTool] = []
        for type in inputTypes {
            for tool in FileTool.tools(for: type, selectionCount: selectionCount) where seen.insert(tool).inserted {
                tools.append(tool)
            }
        }
        return tools.map { tool in
            WheelSegment(id: tool.rawValue, title: tool.title, systemImage: tool.icon, fileTool: tool)
        }
    }
}
