import SwiftUI

/// General behavior: launch at login, click/animation, new-tab defaults, and the
/// multi-display policy.
struct GeneralView: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        Form {
            Section {
                Toggle("Launch MacDring at login", isOn: $preferences.launchAtLogin)
                if let error = preferences.launchAtLoginError {
                    Text("Couldn't update login item: \(error)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Opening drawers") {
                Toggle("Open items with a single click", isOn: $preferences.launchOnSingleClick)
                VStack(alignment: .leading) {
                    Text("Open / close animation: \(Int(preferences.animationMs)) ms")
                    Slider(value: $preferences.animationMs, in: 0...300, step: 10)
                }
            }

            Section("New tab defaults") {
                Toggle("Open on hover instead of click", isOn: $preferences.newTabOpenOnHover)
                Toggle("Close drawer when you click elsewhere", isOn: $preferences.newTabAutoHide)
                Picker("When idle", selection: $preferences.newTabConcealment) {
                    ForEach(TabConcealment.allCases) { Text($0.displayName).tag($0) }
                }
                Stepper("Grid columns: \(Int(preferences.gridColumns))", value: $preferences.gridColumns, in: 1...10)
                Stepper("Grid rows: \(Int(preferences.gridRows))", value: $preferences.gridRows, in: 1...12)
                Text("These apply to newly created tabs. Existing tabs keep their own settings (edit them in the Tabs pane).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Multiple displays") {
                Picker("When a tab's display is disconnected", selection: $preferences.disconnectPolicy) {
                    ForEach(DisconnectPolicy.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Float tabs", selection: $preferences.tabWindowLevel) {
                    ForEach(TabWindowLevel.allCases) { Text($0.displayName).tag($0) }
                }
                Text("Tabs are anchored by a stable display identity and a fractional edge position, so they return to the same spot after a restart, resolution change, or reconnection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear { preferences.refreshLaunchAtLoginStatus() }
    }
}
