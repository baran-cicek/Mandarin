import Foundation
import UniformTypeIdentifiers

/// CSV↔TSV is just a delimiter swap over simple text — doing it natively
/// is both faster and more reliable than routing it through LibreOffice's
/// whole spreadsheet engine for what's really a text transform. Handles
/// RFC4180-style quoted CSV fields (embedded commas/newlines/escaped
/// quotes); TSV has no quoting convention, so a field's own tabs/newlines
/// are flattened to spaces rather than corrupting the column structure.
public final class CSVTSVConverter: Converter {
    public init() {}

    public func canConvert(from: UTType, to: UTType) -> Bool {
        (from == .commaSeparatedText && to == .tabSeparatedText) || (from == .tabSeparatedText && to == .commaSeparatedText)
    }

    public func convert(input: URL, output: URL, options: ConversionOptions, progress: @escaping (Double) -> Void) async throws -> ConversionResult {
        progress(0)
        var text = try String(contentsOf: input, encoding: .utf8)
        // Drop exactly one trailing line ending before parsing — otherwise
        // splitting "a\nb\n" on "\n" yields a spurious empty trailing row.
        if text.hasSuffix("\r\n") {
            text.removeLast(2)
        } else if text.hasSuffix("\n") || text.hasSuffix("\r") {
            text.removeLast()
        }

        let inputType = (try? input.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? .commaSeparatedText
        let rows = inputType == .tabSeparatedText ? Self.parseTSV(text) : Self.parseCSV(text)
        try Task.checkCancellation()
        progress(0.6)

        let outputType = UTType(filenameExtension: output.pathExtension) ?? .commaSeparatedText
        let converted: String
        if outputType == .tabSeparatedText {
            converted = rows.map { row in
                row.map { $0.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ") }.joined(separator: "\t")
            }.joined(separator: "\n")
        } else {
            converted = rows.map { row in row.map(Self.csvEscape).joined(separator: ",") }.joined(separator: "\n")
        }

        try (converted + "\n").write(to: output, atomically: true, encoding: .utf8)
        progress(1.0)
        return ConversionResult(outputURL: output)
    }

    private static func parseTSV(_ text: String) -> [[String]] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            line.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
                .split(separator: "\t", omittingEmptySubsequences: false)
                .map(String.init)
        }
    }

    private static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var insideQuotes = false
        let chars = Array(text)
        var i = 0

        while i < chars.count {
            let c = chars[i]
            if insideQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" {
                        currentField.append("\"")
                        i += 2
                    } else {
                        insideQuotes = false
                        i += 1
                    }
                } else {
                    currentField.append(c)
                    i += 1
                }
                continue
            }

            switch c {
            case "\"":
                insideQuotes = true
                i += 1
            case ",":
                currentRow.append(currentField)
                currentField = ""
                i += 1
            case "\n", "\r":
                currentRow.append(currentField)
                currentField = ""
                rows.append(currentRow)
                currentRow = []
                if c == "\r", i + 1 < chars.count, chars[i + 1] == "\n" { i += 1 }
                i += 1
            default:
                currentField.append(c)
                i += 1
            }
        }
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            rows.append(currentRow)
        }
        return rows
    }

    private static func csvEscape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
