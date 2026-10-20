import Foundation
import ServiceManagement
import UniformTypeIdentifiers

public final class SettingsStore: ObservableObject {
    private let defaults = UserDefaults.standard

    /// Public (along with `JobQueue`/`Job`) so the headless `MandarinConvert`
    /// CLI can point output at a specific folder for test runs.
    @Published public var customOutputFolderPath: String? {
        didSet { defaults.set(customOutputFolderPath, forKey: Keys.customOutputFolderPath) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            applyLaunchAtLogin(launchAtLogin)
        }
    }

    /// Which modifier key opens which wheel. Always a bijection over the
    /// three wheel kinds — `setTriggerKey` swaps instead of duplicating.
    @Published private(set) var triggerKeyMapping: [WheelKind: TriggerKey] {
        didSet { saveTriggerKeyMapping() }
    }

    /// Convert targets the user has turned off — identified by `UTType`
    /// identifier string. Checked by `WheelSegment.convertSegments`, so a
    /// disabled format just never appears on the Convert wheel again.
    @Published public private(set) var disabledFormatIdentifiers: Set<String> {
        didSet { defaults.set(Array(disabledFormatIdentifiers), forKey: Keys.disabledFormats) }
    }

    private enum Keys {
        static let customOutputFolderPath = "customOutputFolderPath"
        static let launchAtLogin = "launchAtLogin"
        static let triggerKeyMapping = "triggerKeyMapping"
        static let disabledFormats = "disabledFormatIdentifiers"
    }

    private static let defaultTriggerKeyMapping: [WheelKind: TriggerKey] = [
        .convert: .shift,
        .fileTools: .command,
        .fileActions: .control,
    ]

    public init() {
        customOutputFolderPath = defaults.string(forKey: Keys.customOutputFolderPath)
        launchAtLogin = SMAppService.mainApp.status == .enabled
        triggerKeyMapping = Self.loadTriggerKeyMapping(from: defaults)
        disabledFormatIdentifiers = Set(defaults.stringArray(forKey: Keys.disabledFormats) ?? [])
    }

    func save() {
        defaults.set(customOutputFolderPath, forKey: Keys.customOutputFolderPath)
        saveTriggerKeyMapping()
        defaults.set(Array(disabledFormatIdentifiers), forKey: Keys.disabledFormats)
    }

    public func setFormat(_ type: UTType, enabled: Bool) {
        if enabled {
            disabledFormatIdentifiers.remove(type.identifier)
        } else {
            disabledFormatIdentifiers.insert(type.identifier)
        }
    }

    public func isFormatEnabled(_ type: UTType) -> Bool {
        !disabledFormatIdentifiers.contains(type.identifier)
    }

    /// Assigns `key` to `kind`. If another kind already used `key`, the two
    /// kinds' keys are swapped so the mapping stays a bijection.
    func setTriggerKey(_ key: TriggerKey, for kind: WheelKind) {
        guard triggerKeyMapping[kind] != key else { return }
        if let otherKind = triggerKeyMapping.first(where: { $0.value == key && $0.key != kind })?.key {
            triggerKeyMapping[otherKind] = triggerKeyMapping[kind]
        }
        triggerKeyMapping[kind] = key
    }

    private func saveTriggerKeyMapping() {
        let raw = triggerKeyMapping.reduce(into: [String: String]()) { result, pair in
            result[pair.key.rawValue] = pair.value.rawValue
        }
        defaults.set(raw, forKey: Keys.triggerKeyMapping)
    }

    private static func loadTriggerKeyMapping(from defaults: UserDefaults) -> [WheelKind: TriggerKey] {
        guard let raw = defaults.dictionary(forKey: Keys.triggerKeyMapping) as? [String: String] else {
            return defaultTriggerKeyMapping
        }
        var mapping: [WheelKind: TriggerKey] = [:]
        for kind in WheelKind.allCases {
            guard let rawKey = raw[kind.rawValue], let key = TriggerKey(rawValue: rawKey) else {
                return defaultTriggerKeyMapping
            }
            mapping[kind] = key
        }
        let assignedKeys = Set(mapping.values)
        guard assignedKeys.count == WheelKind.allCases.count else { return defaultTriggerKeyMapping }
        return mapping
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("\(AppIdentity.name): failed to update launch-at-login: \(error.localizedDescription)")
        }
    }
}
