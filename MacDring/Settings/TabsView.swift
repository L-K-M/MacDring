import SwiftUI
import AppKit

/// Manage all tabs: a selectable list on the left, a per-tab editor on the
/// right (name, color, glyph, edge, display, position, behavior, hotkey, items).
struct TabsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var store: TabStore
    let registry: DisplayRegistry
    @ObservedObject var router: SettingsRouter

    @State private var selection: UUID?

    var body: some View {
        HSplitView {
            tabList
                .frame(minWidth: 180, maxWidth: 240)

            Group {
                if let id = selection, let tab = store.tab(id: id) {
                    TabEditor(draft: tab, preferences: preferences, store: store, registry: registry)
                        .id(id)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 32)).foregroundStyle(.secondary)
                        Text("Select a tab, or add one with +")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if let requested = router.tabToSelect { selection = requested }
            else if selection == nil { selection = store.tabs.first?.id }
        }
        .onChange(of: router.tabToSelect) { requested in
            if let requested { selection = requested }
        }
    }

    private var tabList: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(store.tabs) { tab in
                    HStack(spacing: 8) {
                        Circle().fill(Color(hexString: tab.colorHex)).frame(width: 11, height: 11)
                        Text(tab.title.isEmpty ? "Untitled" : tab.title).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(tab.anchor.edge.displayName)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .tag(tab.id)
                }
            }

            Divider()
            HStack(spacing: 2) {
                Button(action: addTab) { Image(systemName: "plus") }
                Button(action: removeSelected) { Image(systemName: "minus") }
                    .disabled(selection == nil)
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(6)
        }
    }

    private func addTab() {
        guard let uuid = registry.mainScreenUUID() else { return }
        let tab = Tab(
            title: "New Tab",
            colorHex: preferences.defaultTabColorHex,
            glyph: .symbol("folder.fill"),
            anchor: ScreenAnchor(displayUUID: uuid, edge: .right, position: 0.5, order: store.tabs.count),
            behavior: preferences.newTabBehavior
        )
        store.addTab(tab)
        selection = tab.id
    }

    private func removeSelected() {
        guard let id = selection else { return }
        store.removeTab(id: id)
        selection = store.tabs.first?.id
    }
}

/// Edits one tab. Holds a local `draft` (re-seeded when the selection changes via
/// `.id`) and commits the whole tab to the store on any change.
private struct TabEditor: View {
    @State var draft: Tab
    @ObservedObject var preferences: Preferences
    let store: TabStore
    let registry: DisplayRegistry

    @State private var showingLinkSheet = false
    @State private var linkText = ""

    var body: some View {
        Form {
            Section("Tab") {
                TextField("Name", text: $draft.title)
                ColorPicker("Color", selection: colorBinding, supportsOpacity: false)
                Picker("Glyph", selection: glyphIsSymbolBinding) {
                    Text("SF Symbol").tag(true)
                    Text("Letters / Emoji").tag(false)
                }
                .pickerStyle(.segmented)
                if glyphIsSymbolBinding.wrappedValue {
                    LabeledContent("Symbol") { SymbolPickerView(symbolName: symbolBinding) }
                } else {
                    HStack {
                        TextField("Letters or emoji", text: monogramBinding)
                        Button {
                            NSApp.orderFrontCharacterPalette(nil)
                        } label: {
                            Image(systemName: "face.smiling")
                        }
                        .help("Emoji & Symbols")
                    }
                }
            }

            Section("Placement") {
                Picker("Edge", selection: $draft.anchor.edge) {
                    ForEach(Edge.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Display", selection: $draft.anchor.displayUUID) {
                    ForEach(displayChoices, id: \.uuid) { Text($0.name).tag($0.uuid) }
                }
                VStack(alignment: .leading) {
                    Text("Position along edge")
                    Slider(value: $draft.anchor.position, in: 0...1)
                }
                Toggle("Locked (can't be moved)", isOn: $draft.locked)
            }

            Section("Drawer grid") {
                Stepper("Columns: \(draft.gridColumns)", value: $draft.gridColumns, in: 1...10)
                Stepper("Rows: \(draft.gridRows)", value: $draft.gridRows, in: 1...12)
                Text("The grid size of this tab's drawer. Items can be placed anywhere in it, with gaps.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Behavior") {
                Toggle("Open on hover", isOn: $draft.behavior.openOnHover)
                Toggle("Auto-hide when clicking elsewhere", isOn: $draft.behavior.autoHide)
                Toggle("Keep open after launching an item", isOn: $draft.behavior.keepOpenAfterLaunch)
                LabeledContent("Hotkey") { HotkeyRecorderView(hotkey: $draft.hotkey) }
            }

            Section("Items") {
                if draft.items.isEmpty {
                    Text("No items yet. Add some below, or drag files onto the tab.")
                        .foregroundStyle(.secondary).font(.callout)
                } else {
                    ForEach(draft.items) { item in
                        HStack(spacing: 8) {
                            Image(nsImage: ItemView.resolveIcon(item))
                                .resizable().frame(width: 18, height: 18)
                            Text(item.displayName).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .contextMenu {
                            Button("Remove", role: .destructive) {
                                draft.items.removeAll { $0.id == item.id }
                            }
                        }
                    }
                }
                HStack {
                    Button("Add Files…", action: addFiles)
                    Button("Add Link…") { linkText = ""; showingLinkSheet = true }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onChange(of: draft) { _ in store.updateTab(draft) }
        .sheet(isPresented: $showingLinkSheet) { linkSheet }
    }

    // MARK: Bindings

    private var colorBinding: Binding<Color> {
        Binding(get: { Color(hexString: draft.colorHex) },
                set: { draft.colorHex = $0.hexString })
    }

    private var glyphIsSymbolBinding: Binding<Bool> {
        Binding(
            get: { if case .symbol = draft.glyph { return true } else { return false } },
            set: { isSymbol in
                if isSymbol {
                    if case .symbol = draft.glyph {} else { draft.glyph = .symbol("folder.fill") }
                } else {
                    if case .monogram = draft.glyph {} else { draft.glyph = .monogram("A") }
                }
            }
        )
    }

    private var symbolBinding: Binding<String> {
        Binding(
            get: { if case .symbol(let s) = draft.glyph { return s } else { return "" } },
            set: { draft.glyph = .symbol($0) }
        )
    }

    /// Accepts letters or emoji (capped to a few characters).
    private var monogramBinding: Binding<String> {
        Binding(
            get: { if case .monogram(let m) = draft.glyph { return m } else { return "" } },
            set: { draft.glyph = .monogram(String($0.prefix(3))) }
        )
    }

    private var displayChoices: [(uuid: String, name: String)] {
        var choices: [(uuid: String, name: String)] = []
        for screen in NSScreen.screens {
            if let uuid = registry.uuid(for: screen) {
                choices.append((uuid: uuid, name: screen.localizedName))
            }
        }
        if !choices.contains(where: { $0.uuid == draft.anchor.displayUUID }) {
            choices.append((uuid: draft.anchor.displayUUID, name: "Disconnected display"))
        }
        return choices
    }

    // MARK: Adding items

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Choose apps, files, or folders to add"
        if panel.runModal() == .OK {
            for url in panel.urls {
                draft.items.append(DrawerItem.fromFileURL(url))
            }
        }
    }

    private var linkSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a Link").font(.headline)
            TextField("https://example.com", text: $linkText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
            HStack {
                Spacer()
                Button("Cancel") { showingLinkSheet = false }
                Button("Add") {
                    if let item = DrawerItem.fromLink(linkText) { draft.items.append(item) }
                    showingLinkSheet = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }
}
