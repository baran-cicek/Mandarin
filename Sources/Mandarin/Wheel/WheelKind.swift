import AppKit

enum WheelKind: String, CaseIterable, Codable {
    case convert
    case fileTools
    case fileActions

    var title: String {
        switch self {
        case .convert: return "Convert"
        case .fileTools: return "File Tools"
        case .fileActions: return "File Actions"
        }
    }
}

enum TriggerKey: String, CaseIterable, Codable {
    case shift
    case command
    case control
    case option

    var modifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .shift: return .shift
        case .command: return .command
        case .control: return .control
        case .option: return .option
        }
    }

    var label: String {
        switch self {
        case .shift: return "Shift"
        case .command: return "Command"
        case .control: return "Control"
        case .option: return "Option"
        }
    }
}
