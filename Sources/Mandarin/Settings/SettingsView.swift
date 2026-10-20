import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        TabView {
            GeneralSettingsTab(store: store)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
            KeysSettingsTab(store: store)
                .tabItem {
                    Label("Keys", systemImage: "keyboard")
                }
            FormatsSettingsTab(store: store)
                .tabItem {
                    Label("Formats", systemImage: "list.bullet")
                }
        }
        .frame(width: 440, height: 320)
    }
}

private struct GeneralSettingsTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("Launch \(AppIdentity.name) at login", isOn: $store.launchAtLogin)
            }

            Section("Output Location") {
                Picker("", selection: Binding(
                    get: { store.customOutputFolderPath == nil },
                    set: { useDefault in
                        if useDefault { store.customOutputFolderPath = nil }
                        else if store.customOutputFolderPath == nil { chooseFolder() }
                    }
                )) {
                    Text("Next to the original file").tag(true)
                    Text("Custom folder").tag(false)
                }
                .pickerStyle(.radioGroup)

                if let path = store.customOutputFolderPath {
                    HStack {
                        Text(path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Spacer()
                        Button("Change…", action: chooseFolder)
                    }
                }
            }
        }
        .padding(20)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            store.customOutputFolderPath = url.path
        }
    }
}

private struct KeysSettingsTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section {
                Text("Hold a file/folder drag, then tap a key to open its wheel. Releasing the key keeps the wheel open until you drop or press Escape.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Trigger Keys") {
                ForEach(WheelKind.allCases, id: \.self) { kind in
                    Picker(kind.title, selection: Binding(
                        get: { store.triggerKeyMapping[kind] ?? .shift },
                        set: { store.setTriggerKey($0, for: kind) }
                    )) {
                        ForEach(TriggerKey.allCases, id: \.self) { key in
                            Text(key.label).tag(key)
                        }
                    }
                }
            }
        }
        .padding(20)
    }
}

private struct FormatsSettingsTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Turn off formats you never use to keep the Convert wheel short. Turning one off here never affects the File Tools or File Actions wheels.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 16)

            List(ConverterRegistry.candidateOutputTypes, id: \.identifier) { type in
                Toggle(FormatCatalog.fileExtension(for: type).uppercased(), isOn: Binding(
                    get: { store.isFormatEnabled(type) },
                    set: { store.setFormat(type, enabled: $0) }
                ))
            }
        }
    }
}
