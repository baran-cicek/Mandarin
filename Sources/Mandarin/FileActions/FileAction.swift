import Foundation

/// The six File Actions. Always available for any file/folder/mixed
/// selection — unlike Convert segments, these never depend on the
/// Converter registry or a file's type.
enum FileAction: String, CaseIterable {
    case airdrop
    case float
    case copy
    case move
    case copyPath
    case terminal

    var title: String {
        switch self {
        case .airdrop: return "AirDrop"
        case .float: return "Float"
        case .copy: return "Copy"
        case .move: return "Move"
        case .copyPath: return "Copy Path"
        case .terminal: return "Terminal"
        }
    }

    var icon: String {
        switch self {
        case .airdrop: return "dot.radiowaves.left.and.right"
        case .float: return "pin.fill"
        case .copy: return "doc.on.doc"
        case .move: return "folder"
        case .copyPath: return "link"
        case .terminal: return "terminal"
        }
    }
}
