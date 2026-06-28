import SwiftUI

/// Global appearance: drawer material/layout/sizes and tab pill sizing + default
/// color. Per-tab color is edited in the Tabs pane.
struct AppearanceView: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        Form {
            Section("Preview") {
                appearancePreview
                    .frame(height: 108)
                    .frame(maxWidth: .infinity)
            }

            Section("Drawer") {
                Picker("Translucency", selection: $preferences.drawerTranslucency) {
                    ForEach(DrawerTranslucency.allCases) { Text($0.displayName).tag($0) }
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

    // MARK: Live preview

    /// A miniature edge pill + drawer that re-renders as the thickness / radius /
    /// translucency / style / color controls change, so their effect is visible
    /// without closing Settings. Drawn over a faux desktop so translucency reads.
    private var appearancePreview: some View {
        let color = Color(hexString: preferences.defaultTabColorHex)
        let radius = CGFloat(preferences.cornerRadius)
        let pillThickness = max(10, CGFloat(preferences.tabThickness) * 0.5)
        let drawerShape = edgeRoundedRect(edge: .left, radius: radius)
        return ZStack {
            LinearGradient(colors: [.blue.opacity(0.45), .purple.opacity(0.45)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(alignment: .center, spacing: 6) {
                previewPill(color: color)
                    .frame(width: pillThickness, height: 64)
                ZStack {
                    VisualEffectBlur(material: .popover, blendingMode: .withinWindow)
                    Color(nsColor: .windowBackgroundColor)
                        .opacity(preferences.drawerTranslucency.backingOpacity)
                    color.opacity(0.10)
                    HStack(spacing: 10) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 5)
                                .fill(.white.opacity(0.55))
                                .frame(width: 22, height: 22)
                        }
                    }
                }
                .clipShape(drawerShape)
                .overlay(drawerShape.stroke(.white.opacity(0.25), lineWidth: 1))
                .frame(width: 150, height: 84)
                Spacer(minLength: 0)
            }
            .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func previewPill(color: Color) -> some View {
        let shape: AnyShape = preferences.tabStyle == .classic
            ? AnyShape(ClassicTabShape(edge: .left))
            : AnyShape(edgeRoundedRect(edge: .left, radius: CGFloat(preferences.cornerRadius)))
        return shape
            .fill(color.opacity(0.9))
            .overlay(shape.stroke(.white.opacity(0.35), lineWidth: 1))
    }
}
