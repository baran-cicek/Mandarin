import UniformTypeIdentifiers

public final class ConverterRegistry {
    public static let shared = ConverterRegistry()

    /// Every output type Mandarin might offer, in Convert-wheel display
    /// order. Shared with `WheelSegment` so the wheel and the registry
    /// never disagree on what "all known targets" means. Each format
    /// appears in exactly one of these tables — e.g. PDF lives only in
    /// `ImageFormats`, spreadsheets' PDF export reuses that same entry
    /// rather than re-declaring it.
    static let candidateOutputTypes: [UTType] =
        ImageFormats.outputs.map(\.type)
        + MediaFormats.all.map(\.type)
        + DocumentFormats.outputs.map(\.type)
        + SpreadsheetFormats.outputs.map(\.type)
        + SubtitleFormats.outputs.map(\.type)
        + ArchiveFormats.outputs.map(\.type)

    private let converters: [Converter]
    let imageConverter = ImageConverter()
    let avFoundationConverter = AVFoundationMediaConverter()
    let ffmpegConverter = FFmpegMediaConverter()
    let pdfExportConverter = PDFExportConverter()
    let nativeDocumentConverter = NativeDocumentConverter()
    let pandocDocumentConverter = PandocDocumentConverter()
    let csvtsvConverter = CSVTSVConverter()
    let libreOfficeConverter = LibreOfficeConverter()
    let subtitleConverter = SubtitleConverter()
    let archiveConverter = ArchiveConverter()

    private init() {
        converters = [
            imageConverter, avFoundationConverter, ffmpegConverter,
            pdfExportConverter, nativeDocumentConverter, pandocDocumentConverter,
            csvtsvConverter, libreOfficeConverter, subtitleConverter, archiveConverter,
        ]
    }

    func converter(from: UTType, to: UTType) -> Converter? {
        converters.first { $0.canConvert(from: from, to: to) }
    }

    /// Output formats available for `inputType` right now, in display order,
    /// used to populate the Convert wheel for a dragged file.
    public func availableTargets(for inputType: UTType) -> [UTType] {
        Self.candidateOutputTypes.filter { outputType in
            outputType != inputType && converter(from: inputType, to: outputType) != nil
        }
    }
}
