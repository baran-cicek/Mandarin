import Foundation
import UniformTypeIdentifiers

struct SubtitleCue {
    let start: Double
    let end: Double
    let text: String
}

/// SRT↔VTT↔TXT, entirely native — both formats are simple enough that a
/// small timestamp-tolerant parser (keyed off any line containing `-->`,
/// so it doesn't care whether a numeric/identifier line precedes it, or
/// whether the decimal separator is `,` or `.`) beats shelling out.
enum SubtitleParsing {
    static func parse(_ content: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        let lines = content.components(separatedBy: .newlines)
        var i = 0
        while i < lines.count {
            guard let range = lines[i].range(of: "-->") else {
                i += 1
                continue
            }
            let startString = lines[i][lines[i].startIndex..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let endString = lines[i][range.upperBound...]
                .trimmingCharacters(in: .whitespaces)
                .components(separatedBy: " ").first ?? ""

            guard let start = timestamp(from: startString), let end = timestamp(from: endString) else {
                i += 1
                continue
            }
            i += 1
            var textLines: [String] = []
            while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                textLines.append(lines[i])
                i += 1
            }
            cues.append(SubtitleCue(start: start, end: end, text: textLines.joined(separator: "\n")))
        }
        return cues
    }

    static func writeSRT(_ cues: [SubtitleCue]) -> String {
        cues.enumerated().map { index, cue in
            "\(index + 1)\n\(timestampString(cue.start, decimalSeparator: ",")) --> \(timestampString(cue.end, decimalSeparator: ","))\n\(cue.text)"
        }.joined(separator: "\n\n") + "\n"
    }

    static func writeVTT(_ cues: [SubtitleCue]) -> String {
        "WEBVTT\n\n" + cues.map { cue in
            "\(timestampString(cue.start, decimalSeparator: ".")) --> \(timestampString(cue.end, decimalSeparator: "."))\n\(cue.text)"
        }.joined(separator: "\n\n") + "\n"
    }

    static func writeTXT(_ cues: [SubtitleCue]) -> String {
        cues.map(\.text).joined(separator: "\n\n") + "\n"
    }

    private static func timestamp(from string: String) -> Double? {
        let normalized = string.replacingOccurrences(of: ",", with: ".")
        let parts = normalized.split(separator: ":").map(String.init)
        guard parts.count == 3, let hours = Double(parts[0]), let minutes = Double(parts[1]), let seconds = Double(parts[2]) else {
            return nil
        }
        return hours * 3600 + minutes * 60 + seconds
    }

    private static func timestampString(_ seconds: Double, decimalSeparator: String) -> String {
        let totalMillis = Int((seconds * 1000).rounded())
        let hours = totalMillis / 3_600_000
        let minutes = (totalMillis % 3_600_000) / 60_000
        let secs = (totalMillis % 60_000) / 1000
        let millis = totalMillis % 1000
        return String(format: "%02d:%02d:%02d%@%03d", hours, minutes, secs, decimalSeparator, millis)
    }
}

public final class SubtitleConverter: Converter {
    public init() {}

    public func canConvert(from: UTType, to: UTType) -> Bool {
        let readable: Set<UTType> = [SubtitleFormats.srt, SubtitleFormats.vtt]
        let writable: Set<UTType> = [SubtitleFormats.srt, SubtitleFormats.vtt, .plainText]
        return readable.contains(from) && writable.contains(to) && from != to
    }

    public func convert(input: URL, output: URL, options: ConversionOptions, progress: @escaping (Double) -> Void) async throws -> ConversionResult {
        progress(0)
        let content = try String(contentsOf: input, encoding: .utf8)
        let cues = SubtitleParsing.parse(content)
        guard !cues.isEmpty else {
            throw ConversionError.toolFailed("No subtitle cues found — this doesn't look like a valid SRT/VTT file.")
        }
        try Task.checkCancellation()
        progress(0.6)

        let outputType = UTType(filenameExtension: output.pathExtension) ?? .data
        let text: String
        switch outputType {
        case SubtitleFormats.vtt: text = SubtitleParsing.writeVTT(cues)
        case .plainText: text = SubtitleParsing.writeTXT(cues)
        default: text = SubtitleParsing.writeSRT(cues)
        }

        try text.write(to: output, atomically: true, encoding: .utf8)
        progress(1.0)
        return ConversionResult(outputURL: output)
    }
}
