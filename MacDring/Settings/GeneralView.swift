import SwiftUI

/// General behavior: launch at login, drawer interaction (applies to all tabs),
/// new-tab defaults, and the multi-display policy.
struct GeneralView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var store: TabStore

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
                Toggle("Open on hover instead of click", isOn: openOnHoverBinding)
                Toggle("Close drawer when you click elsewhere", isOn: autoHideBinding)
                VStack(alignment: .leading) {
                    Text("Open / close animation: \(Int(preferences.animationMs)) ms")
                    Slider(value: $preferences.animationMs, in: 0...300, step: 10)
                }
                Text("Hover and close behavior apply to all tabs; you can still override an individual tab in the Tabs pane.")
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

    // MARK: Global drawer-behavior bindings

    // These set the new-tab default *and* apply to every existing tab, so toggling
    // them takes effect immediately (the Tabs pane still overrides per tab).

    // The displayed state reflects the existing tabs (on only when *every* tab has
    // it on), so it can't show "off" while a tab still closes; it falls back to the
    // new-tab default when there are no tabs yet.

    private var openOnHoverBinding: Binding<Bool> {
        Binding(
            get: { store.tabs.isEmpty ? preferences.newTabOpenOnHover : store.tabs.allSatisfy { $0.behavior.openOnHover } },
            set: { newValue in
                preferences.newTabOpenOnHover = newValue
                store.updateAllBehaviors { $0.openOnHover = newValue }
            }
        )
    }

    private var autoHideBinding: Binding<Bool> {
        Binding(
            get: { store.tabs.isEmpty ? preferences.newTabAutoHide : store.tabs.allSatisfy { $0.behavior.autoHide } },
            set: { newValue in
                preferences.newTabAutoHide = newValue
                store.updateAllBehaviors { $0.autoHide = newValue }
            }
        )
    }
}
