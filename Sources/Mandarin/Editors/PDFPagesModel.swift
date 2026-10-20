import AppKit
import Foundation
import PDFKit

@MainActor
public final class PDFPagesModel: ObservableObject {
    public let source: URL
    /// Source files in index order; the first is the one that was opened.
    public private(set) var sources: [URL]
    @Published public private(set) var list: PDFPageList
    @Published public var selection: Set<UUID> = []
    @Published private(set) var thumbnails: [String: NSImage] = [:]
    @Published public var errorMessage: String?

    private var pageSizes: [[CGSize]] = []
    private var inFlight: Set<String> = []
    private let queue = DispatchQueue(label: "pdf-thumbnails", qos: .userInitiated)
    private var documentsOnQueue: [Int: PDFDocument] = [:]
    private var anchor: UUID?

    public static func load(_ url: URL) async throws -> PDFPagesModel {
        let count = try await Task.detached(priority: .userInitiated) { () -> Int in
            guard let document = PDFDocument(url: url), !document.isLocked, document.pageCount > 0 else { throw ConversionError.cannotReadInput }
            return document.pageCount
        }.value
        return PDFPagesModel(source: url, pageCount: count)
    }

    private init(source: URL, pageCount: Int) {
        self.source = source
        self.sources = [source]
        self.list = PDFPageList(documentIndex: 0, pageCount: pageCount)
    }

    // MARK: Editing

    public func addPDF(_ url: URL) async {
        do {
            let count = try await Task.detached(priority: .userInitiated) { () -> Int in
                guard let document = PDFDocument(url: url), !document.isLocked, document.pageCount > 0 else { throw ConversionError.cannotReadInput }
                return document.pageCount
            }.value
            sources.append(url)
            list.append(documentIndex: sources.count - 1, pageCount: count)
        } catch {
            errorMessage = "Couldn't read \(url.lastPathComponent) as a PDF."
        }
    }

    public func select(_ id: UUID, extend: Bool, range: Bool) {
        if range, let anchor, let a = list.items.firstIndex(where: { $0.id == anchor }), let b = list.items.firstIndex(where: { $0.id == id }) {
            selection = Set(list.items[min(a, b)...max(a, b)].map(\.id))
        } else if extend {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            anchor = id
        } else {
            selection = [id]
            anchor = id
        }
    }

    public func selectAll() { selection = Set(list.items.map(\.id)) }
    public func deleteSelected() { list.delete(selection); selection = [] }
    public func rotateSelected(by degrees: Int) { list.rotate(selection, by: degrees) }
    public func moveSelected(by step: Int) { list.shift(selection, by: step) }

    /// Drag-and-drop: move `ids` (or the selection, if the dragged page is part of it) before `target`.
    public func drop(_ draggedID: UUID, before target: UUID) {
        let ids = selection.contains(draggedID) ? selection : [draggedID]
        guard let offset = list.items.firstIndex(where: { $0.id == target }) else { return }
        list.move(ids, toOffset: offset)
    }

    public func dropAtEnd(_ draggedID: UUID) {
        let ids = selection.contains(draggedID) ? selection : [draggedID]
        list.move(ids, toOffset: list.items.count)
    }

    public var hasChanges: Bool {
        let identity = list.items.enumerated().allSatisfy { $0.element.documentIndex == 0 && $0.element.pageIndex == $0.offset && $0.element.rotation == 0 }
        return !identity
    }

    public func position(of id: UUID) -> Int? { list.items.firstIndex { $0.id == id }.map { $0 + 1 } }

    // MARK: Thumbnails (loaded lazily, off the main thread, from private PDFDocument instances)

    public func thumbnail(for item: PDFPageItem) -> NSImage? {
        thumbnails[Self.key(item)]
    }

    private static func key(_ item: PDFPageItem) -> String { "\(item.documentIndex):\(item.pageIndex):\(item.rotation)" }

    public func requestThumbnail(for item: PDFPageItem) {
        let key = Self.key(item)
        guard thumbnails[key] == nil, !inFlight.contains(key) else { return }
        inFlight.insert(key)
        let url = sources[item.documentIndex]
        let index = item.documentIndex
        queue.async { [weak self] in
            guard let self else { return }
            let document = self.documentsOnQueue[index] ?? PDFDocument(url: url)
            self.documentsOnQueue[index] = document
            var image: NSImage?
            if let page = document?.page(at: item.pageIndex)?.copy() as? PDFPage {
                page.rotation = ((page.rotation + item.rotation) % 360 + 360) % 360
                image = page.thumbnail(of: CGSize(width: 220, height: 280), for: .mediaBox)
            }
            DispatchQueue.main.async {
                self.inFlight.remove(key)
                if let image { self.thumbnails[key] = image }
            }
        }
    }
}
