import SwiftUI

/// General behavior: launch at login, the global drawer-interaction defaults (which
/// every tab follows unless it overrides them in the Tabs pane), new-tab defaults,
/// and the multi-display policy.
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

            Section("Drawers") {
                Toggle("Open items with a single click", isOn: $preferences.launchOnSingleClick)
                Toggle("Open on hover instead of click", isOn: $preferences.newTabOpenOnHover)
                Toggle("Close drawer when you click elsewhere", isOn: $preferences.newTabAutoHide)
                VStack(alignment: .leading) {
                    Text("Open / close animation: \(Int(preferences.animationMs)) ms")
                    Slider(value: $preferences.animationMs, in: 0...300, step: 10)
                }
                Text("Hover and close are the default for every tab. A tab set to a specific value in the Tabs pane keeps it regardless of this — change it back to “Use global default” there to follow this again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("New tab defaults") {
                Picker("When idle", selection: $preferences.newTabConcealment) {
                    ForEach(TabConcealment.allCases) { Text($0.displayName).tag($0) }
                }
                Stepper("Grid columns: \(Int(preferences.gridColumns))", value: $preferences.gridColumns, in: 1...10)
                Stepper("Grid rows: \(Int(preferences.gridRows))", value: $preferences.gridRows, in: 1...12)
                Text("Apply to newly created tabs. Existing tabs keep their own (edit them in the Tabs pane).")
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
