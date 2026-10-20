import Foundation
import PDFKit

/// One page in the page tool: where it came from and how much it has been rotated.
public struct PDFPageItem: Identifiable, Equatable {
    public let id: UUID
    public let documentIndex: Int
    public let pageIndex: Int
    public var rotation: Int          // extra clockwise degrees: 0, 90, 180, 270

    public init(documentIndex: Int, pageIndex: Int, rotation: Int = 0, id: UUID = UUID()) {
        self.id = id
        self.documentIndex = documentIndex
        self.pageIndex = pageIndex
        self.rotation = rotation
    }
}

/// Page order, deletion and rotation with no UI or PDFKit involved.
public struct PDFPageList: Equatable {
    public private(set) var items: [PDFPageItem] = []

    public init() {}

    public init(documentIndex: Int, pageCount: Int) {
        append(documentIndex: documentIndex, pageCount: pageCount)
    }

    public mutating func append(documentIndex: Int, pageCount: Int) {
        items += (0..<max(pageCount, 0)).map { PDFPageItem(documentIndex: documentIndex, pageIndex: $0) }
    }

    /// Moves the selected pages (keeping their relative order) so they sit
    /// before the page that is currently at `offset` (`items.count` = the end).
    public mutating func move(_ ids: Set<UUID>, toOffset offset: Int) {
        let moving = items.filter { ids.contains($0.id) }
        guard !moving.isEmpty else { return }
        let clamped = min(max(offset, 0), items.count)
        let before = items.prefix(clamped).filter { ids.contains($0.id) }.count
        var rest = items.filter { !ids.contains($0.id) }
        rest.insert(contentsOf: moving, at: min(clamped - before, rest.count))
        items = rest
    }

    /// Nudges the selection one step earlier/later; keyboard alternative to dragging.
    public mutating func shift(_ ids: Set<UUID>, by step: Int) {
        guard let first = items.firstIndex(where: { ids.contains($0.id) }),
              let last = items.lastIndex(where: { ids.contains($0.id) }) else { return }
        if step < 0 { move(ids, toOffset: max(first - 1, 0)) } else { move(ids, toOffset: min(last + 2, items.count)) }
    }

    public mutating func delete(_ ids: Set<UUID>) {
        items.removeAll { ids.contains($0.id) }
    }

    public mutating func rotate(_ ids: Set<UUID>, by degrees: Int) {
        for index in items.indices where ids.contains(items[index].id) {
            items[index].rotation = (((items[index].rotation + degrees) % 360) + 360) % 360
        }
    }

    public func subset(_ ids: Set<UUID>) -> [PDFPageItem] {
        items.filter { ids.contains($0.id) }
    }
}

public enum PDFPageBuilder {
    /// Builds a new document from `items`, copying pages out of `documents`.
    public static func build(_ items: [PDFPageItem], from documents: [PDFDocument]) throws -> PDFDocument {
        guard !items.isEmpty else { throw ConversionError.toolFailed("There are no pages to save.") }
        let result = PDFDocument()
        for item in items {
            try Task.checkCancellation()
            guard documents.indices.contains(item.documentIndex),
                  let original = documents[item.documentIndex].page(at: item.pageIndex),
                  let page = original.copy() as? PDFPage else {
                throw ConversionError.cannotReadInput
            }
            page.rotation = ((page.rotation + item.rotation) % 360 + 360) % 360
            result.insert(page, at: result.pageCount)
        }
        return result
    }

    /// Opens the source files, builds and writes the result.
    public static func export(_ items: [PDFPageItem], sources: [URL], to output: URL) throws -> ConversionResult {
        let documents = try sources.map { url -> PDFDocument in
            guard let document = PDFDocument(url: url) else { throw ConversionError.cannotReadInput }
            return document
        }
        let built = try build(items, from: documents)
        guard built.write(to: output) else { throw ConversionError.cannotWriteOutput }
        return ConversionResult(outputURL: output)
    }
}
