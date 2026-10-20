import UniformTypeIdentifiers

/// The "Spreadsheets" format family. PDF export reuses the existing
/// `UTType.pdf` already registered by `ImageFormats` — not re-declared
/// here — so it only ever appears once in the Convert wheel.
public enum SpreadsheetFormats {
    struct Format {
        let type: UTType
        let fileExtension: String
        let icon: String
    }

    public static let xlsx = UTType.known(nil, ext: "xlsx")
    static let ods = UTType.known(nil, ext: "ods")
    static let xls = UTType.known(nil, ext: "xls")

    /// Output formats, in Convert-wheel order. XLS is input-only (per
    /// spec) and deliberately excluded.
    static let outputs: [Format] = [
        Format(type: xlsx, fileExtension: "xlsx", icon: "tablecells"),
        Format(type: ods, fileExtension: "ods", icon: "tablecells"),
        Format(type: .commaSeparatedText, fileExtension: "csv", icon: "tablecells"),
        Format(type: .tabSeparatedText, fileExtension: "tsv", icon: "tablecells"),
    ]

    static func format(for type: UTType) -> Format? {
        outputs.first { $0.type == type }
    }
}
