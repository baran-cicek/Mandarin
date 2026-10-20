import UniformTypeIdentifiers

/// Single place that knows how to look up a display extension/icon for any
/// output type — image, media, document, spreadsheet, subtitle, or
/// archive — so `OutputPathPlanner`, `WheelSegment`, and `JobQueue` don't
/// each duplicate the "check every table" logic.
public enum FormatCatalog {
    public static func fileExtension(for type: UTType) -> String {
        ImageFormats.format(for: type)?.fileExtension
            ?? MediaFormats.format(for: type)?.fileExtension
            ?? DocumentFormats.format(for: type)?.fileExtension
            ?? SpreadsheetFormats.format(for: type)?.fileExtension
            ?? SubtitleFormats.format(for: type)?.fileExtension
            ?? ArchiveFormats.format(for: type)?.fileExtension
            ?? type.preferredFilenameExtension
            ?? type.identifier
    }

    public static func icon(for type: UTType) -> String {
        ImageFormats.format(for: type)?.icon
            ?? MediaFormats.format(for: type)?.icon
            ?? DocumentFormats.format(for: type)?.icon
            ?? SpreadsheetFormats.format(for: type)?.icon
            ?? SubtitleFormats.format(for: type)?.icon
            ?? ArchiveFormats.format(for: type)?.icon
            ?? "doc"
    }
}
