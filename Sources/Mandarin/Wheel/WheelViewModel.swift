import Foundation
import UniformTypeIdentifiers

final class WheelViewModel: ObservableObject {
    @Published var kind: WheelKind
    @Published var segments: [WheelSegment]
    @Published var hoveredIndex: Int?
    /// Shown in the wheel's center when `segments` is empty (Convert only —
    /// File Actions/Tools are never empty).
    @Published var emptyStateMessage: String = ""

    init(kind: WheelKind) {
        self.kind = kind
        self.segments = []
    }

    /// Switches the wheel to `newKind`, (re)computing segments. For
    /// `.convert`, segments are the intersection of targets valid for every
    /// dragged file's type — a mixed selection only offers a format that
    /// works for all of them — minus anything the user disabled in
    /// Settings. File Actions are always the full, fixed list regardless
    /// of type or selection size.
    func setKind(_ newKind: WheelKind, sourceURLs: [URL], disabledFormats: Set<String> = []) {
        kind = newKind
        hoveredIndex = nil

        switch newKind {
        case .convert:
            let types = sourceURLs.map(Self.contentType(of:))
            segments = WheelSegment.convertSegments(for: types).filter { segment in
                guard let outputType = segment.outputType else { return true }
                return !disabledFormats.contains(outputType.identifier)
            }
            emptyStateMessage = segments.isEmpty ? Self.emptyConvertMessage(for: types) : ""
        case .fileActions:
            segments = WheelSegment.fileActionSegments()
            emptyStateMessage = ""
        case .fileTools:
            let types = sourceURLs.map(Self.contentType(of:))
            segments = WheelSegment.fileToolSegments(for: types, selectionCount: sourceURLs.count)
            emptyStateMessage = ""
        }
    }

    private static func emptyConvertMessage(for types: [UTType]) -> String {
        let extensions = Array(Set(types.map { $0.preferredFilenameExtension ?? $0.identifier })).sorted()
        guard !extensions.isEmpty else { return "No conversions for this file type" }
        if extensions.count == 1 {
            return "No conversions for this file type (.\(extensions[0]))"
        }
        return "No common conversions for mixed types (.\(extensions.joined(separator: ", .")))"
    }

    private static func contentType(of url: URL) -> UTType {
        (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: url.pathExtension)
            ?? .data
    }
}
