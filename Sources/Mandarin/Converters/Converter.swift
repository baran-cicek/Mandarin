import Foundation
import UniformTypeIdentifiers

public struct ConversionOptions {
    public var quality: Double = 0.9
    public init(quality: Double = 0.9) {
        self.quality = quality
    }
}

/// `outputURL` is normally just the `output` the converter was handed, but
/// a few routes (multi-page PDF/slide image export) produce a sibling
/// *folder* instead of that single planned file, so the real location
/// comes back here rather than being assumed. `warning` surfaces as the
/// HUD's success message for "best effort" routes (e.g. office-document
/// conversions through LibreOffice) instead of a plain "Done" — never a
/// silent, unqualified success for a route that's known to be shaky.
public struct ConversionResult {
    public let outputURL: URL
    public let warning: String?
    public init(outputURL: URL, warning: String? = nil) {
        self.outputURL = outputURL
        self.warning = warning
    }
}

public enum ConversionError: LocalizedError {
    case cannotReadInput
    case cannotWriteOutput
    case missingTool(name: String, installHint: String)
    case toolFailed(String)
    case noConverterAvailable
    case unsupportedRoute(String)

    public var errorDescription: String? {
        switch self {
        case .cannotReadInput:
            return "Couldn't read the source file."
        case .cannotWriteOutput:
            return "Couldn't write the output file."
        case .missingTool(let name, let installHint):
            return "\(name) isn't installed. \(installHint)"
        case .toolFailed(let message):
            return message
        case .noConverterAvailable:
            return "No converter available for this format."
        case .unsupportedRoute(let message):
            return message
        }
    }

    /// Trims a raw multi-line tool error dump (ffmpeg/pandoc stderr, etc.)
    /// down to its first non-blank line — the HUD shows one line, and the
    /// first is usually the most specific one anyway (the rest tends to be
    /// context or a restatement).
    public static func toolFailed(fromRawOutput rawOutput: String) -> ConversionError {
        let firstLine = rawOutput
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        return .toolFailed(firstLine ?? "The tool reported an error with no further detail.")
    }
}

protocol Converter {
    func canConvert(from: UTType, to: UTType) -> Bool
    func convert(input: URL, output: URL, options: ConversionOptions, progress: @escaping (Double) -> Void) async throws -> ConversionResult
}
