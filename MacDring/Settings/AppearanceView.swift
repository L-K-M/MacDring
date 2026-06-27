import SwiftUI

/// Global appearance: drawer material/layout/sizes and tab pill sizing + default
/// color. Per-tab color is edited in the Tabs pane.
struct AppearanceView: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        Form {
            Section("Drawer") {
                Picker("Material", selection: $preferences.drawerMaterial) {
                    ForEach(DrawerMaterial.allCases) { Text($0.displayName).tag($0) }
                }
                VStack(alignment: .leading) {
                    Text("Icon size: \(Int(preferences.iconSize)) pt")
                    Slider(value: $preferences.iconSize, in: 32...128, step: 4)
                }
                VStack(alignment: .leading) {
                    Text("Corner radius: \(Int(preferences.cornerRadius)) pt")
                    Slider(value: $preferences.cornerRadius, in: 0...24, step: 1)
                }
            }

            Section("Tabs") {
                Picker("Style", selection: $preferences.tabStyle) {
                    ForEach(TabStyle.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                VStack(alignment: .leading) {
                    Text("Tab thickness: \(Int(preferences.tabThickness)) pt")
                    Slider(value: $preferences.tabThickness, in: 24...64, step: 1)
                }
                VStack(alignment: .leading) {
                    Text("Auto-fade opacity: \(Int(preferences.fadedOpacity * 100))%")
                    Slider(value: $preferences.fadedOpacity, in: 0.05...0.9, step: 0.05)
                }
                Toggle("Show tab labels", isOn: $preferences.showTabLabels)
                Text("Side tabs (left/right edges) print their name vertically, so longer names fit. Auto-fade opacity sets how faint an idle auto-fading tab gets (Tabs → When idle).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ColorPicker("Default color for new tabs", selection: defaultColorBinding, supportsOpacity: false)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var defaultColorBinding: Binding<Color> {
        Binding(
            get: { Color(hexString: preferences.defaultTabColorHex) },
            set: { preferences.defaultTabColorHex = $0.hexString }
        )
    }
}
