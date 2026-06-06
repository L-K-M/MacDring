import SwiftUI
import UniformTypeIdentifiers

/// The panel that expands from a tab. Its content depends on the tab's kind:
/// - **items**: a freely-arranged grid/list (slots + gaps, drag-to-reorder,
///   drop-to-add, remove).
/// - **folder**: a read-only live listing of a directory (launch + reveal; items
///   are draggable *out* to Finder/other apps).
/// - **notes**: a text editor.
///
/// File drops are routed by what they land on: an **app** opens the files with
/// it, a **folder** receives them, and an empty slot / the background adds them
/// (items tab) or files them into the mirrored directory (folder tab).
struct DrawerView: View {
    @ObservedObject var model: DrawerModel
    @ObservedObject var preferences: Preferences

    @State private var dragging: DrawerItem?
    @State private var dragOffset: CGSize = .zero
    @State private var slotFrames: [Int: CGRect] = [:]
    @State private var dropTargetSlot: Int?      // internal reorder target
    // The external file-drop target slot lives on the model (`model.fileDropSlot`)
    // so the AppKit-driven drop delegate can update it during a drag.

    private let contentSpace = "macdring.drawer.content"
    private var columns: Int { max(1, model.columns) }
    private var maxSlot: Int { model.items.map(\.slot).max() ?? -1 }
    private var rows: Int {
        DrawerMetrics.gridRowCount(configuredRows: model.rows, maxSlot: maxSlot,
                                   itemCount: model.items.count, columns: columns)
    }
    private var cellHeight: CGFloat { CGFloat(preferences.iconSize) + 26 }
    /// Only `.items` tabs support internal reorder / remove.
    private var editable: Bool { model.kind == .items }

    var body: some View {
        // The two corners touching the screen edge stay sharp; the inward corners
        // are rounded — so the drawer reads as sliding flush out of the edge. An
        // inner corner the tab sits against is squared so the tab joins flush.
        let shape = edgeRoundedRect(edge: model.edge, radius: CGFloat(preferences.cornerRadius),
                                    squareStart: model.squareInnerStart, squareEnd: model.squareInnerEnd)

        VStack(alignment: .leading, spacing: 10) {
            header
            if model.isSearchable { searchBar }
            bodyContent
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            ZStack {
                VisualEffectBlur(material: preferences.drawerMaterial.nsMaterial, blendingMode: .behindWindow)
                Color(hexString: model.colorHex).opacity(0.10)
            }
        )
        .clipShape(shape)
        .overlay(
            shape.stroke(.white.opacity(model.isDropTargeted ? 0.9 : 0.12),
                         lineWidth: model.isDropTargeted ? 2 : 1)
        )
        .onHover { inside in
            if inside { model.onMouseEntered?() } else { model.onMouseExited?() }
        }
        // Report slot frames in this outermost coordinate space — which fills the
        // hosting view — so the AppKit drag destination (`DrawerHostingView`) can map
        // a window-space drop location to a slot. The dragged-item overlay and the
        // reorder gesture share the same space. (File drops themselves are handled in
        // AppKit, not via SwiftUI `.onDrop`, which is unreliable in this panel.)
        .coordinateSpace(name: contentSpace)
        .overlay(alignment: .topLeading) { draggedOverlay }
        .onPreferenceChange(SlotFramesKey.self) { slotFrames = $0; model.slotFrames = $0 }
    }

    @ViewBuilder
    private var bodyContent: some View {
        switch model.kind {
        case .notes:
            if model.notesPreview { notesPreview } else { notesEditor }
        case .items, .folder, .disks, .network, .cloud, .recents:
            if model.isSearching { searchResultsList }
            else if model.items.isEmpty { emptyState }
            else { content }
        }
    }

    // MARK: Type-to-find

    /// A read-only display of the current query — input is driven by `TabController`'s
    /// key monitor (focus is unreliable in the borderless panel), so this isn't an
    /// editable field. The ✕ clears it.
    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.callout).foregroundStyle(.secondary)
            if model.searchQuery.isEmpty {
                Text("Type to filter…").foregroundStyle(.secondary)
            } else {
                Text(model.searchQuery)
            }
            Spacer(minLength: 0)
            if !model.searchQuery.isEmpty {
                Button { model.clearSearch() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Clear filter")
            }
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.10)))
    }

    /// The filtered results as a compact, keyboard-navigable list (Up/Down select,
    /// Return launches — handled by the key monitor). The selected row is tinted.
    private var searchResultsList: some View {
        let results = model.searchResults
        return ScrollView {
            if results.isEmpty {
                Text("No matches for “\(model.searchQuery)”")
                    .foregroundStyle(.secondary).font(.callout)
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
            } else {
                VStack(spacing: 2) {
                    ForEach(results) { item in
                        itemView(item, layout: .list)
                            .padding(.vertical, 3)
                            .padding(.horizontal, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(item.id == model.selectedItemID ? Color.accentColor.opacity(0.30) : .clear))
                    }
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hexString: model.colorHex))
                .frame(width: 10, height: 10)
            Text(model.title.isEmpty ? "Drawer" : model.title)
                .font(.headline)
            Spacer(minLength: 12)
            if model.kind != .notes {
                Text("\(model.items.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if model.kind == .folder {
                headerButton("folder", help: "Open folder in Finder") { model.onOpenFolder?() }
                    .disabled(model.folderURL == nil)
            }
            if model.kind == .notes {
                headerButton(model.notesPreview ? "pencil" : "eye",
                             help: model.notesPreview ? "Edit notes" : "Preview Markdown") {
                    model.notesPreview.toggle()
                }
            if model.kind == .recents {
                headerButton("trash", help: "Clear recent items") { model.onClearRecents?() }
                    .disabled(model.items.isEmpty)
            }
            headerButton(model.locked ? "lock.fill" : "lock.open",
                         help: model.locked ? "Unlock this tab's position" : "Lock this tab's position") {
                model.onToggleLocked?()
            }
            headerButton("gearshape", help: "Configure Tab…") { model.onOpenSettings?() }
        }
    }

    private func headerButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(help)
    }

    // MARK: Notes

    private var notesEditor: some View {
        // No extra inner padding around the editor — the TextEditor's own text inset
        // is enough; the previous `.padding(8)` double-inset the text from the box.
        TextEditor(text: notesBinding)
            .font(.body)
            .scrollContentBackground(.hidden)
            .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.08)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Rendered-Markdown preview of the note (toggled from the header).
    private var notesPreview: some View {
        ScrollView {
            if model.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Nothing to preview yet.")
                    .foregroundStyle(.secondary).font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            } else {
                MarkdownText(text: model.notes)
                    .padding(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.08)))
    }

    private var notesBinding: Binding<String> {
        Binding(get: { model.notes }, set: { model.notes = $0; model.onNotesChanged?($0) })
    }

    // MARK: Items / folder grid

    private var content: some View {
        ScrollView { itemsLayout }
    }

    @ViewBuilder
    private var itemsLayout: some View {
        if preferences.drawerLayout == .grid {
            let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: columns)
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(Array(0..<(rows * columns)), id: \.self) { slot in
                    gridSlot(slot)
                }
            }
        } else {
            VStack(spacing: 2) {
                ForEach(model.items.sorted { $0.slot < $1.slot }) { item in
                    let fileDropHere = model.fileDropSlot == item.slot
                    // Match the grid: a file dragged onto a folder/app is a
                    // "file into / open with" target — give it a distinct ring.
                    let intoTarget = fileDropHere && (item.kind == .folder || item.kind == .application)
                    inCellItem(item)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 4)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(fileDropHere ? 0.16 : 0)))
                        .overlay {
                            if intoTarget {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color(hexString: model.colorHex), lineWidth: 2)
                            }
                        }
                        .background(slotFrameReporter(item.slot))
                }
            }
        }
    }

    private func gridSlot(_ slot: Int) -> some View {
        let item = model.item(atSlot: slot)
        let reorderHere = dropTargetSlot == slot && dragging?.slot != slot
        let fileDropHere = model.fileDropSlot == slot
        // A file dragged onto a folder/app is a "file into / open with" target, not a
        // plain slot drop — give it a distinct ring so the difference is obvious.
        let intoTarget = fileDropHere && (item?.kind == .folder || item?.kind == .application || item?.kind == .trash)
        return ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity((reorderHere || fileDropHere) ? 0.16 : 0))
            if let item { inCellItem(item) }
        }
        .frame(maxWidth: .infinity)
        .frame(height: cellHeight)
        .overlay {
            if intoTarget {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color(hexString: model.colorHex), lineWidth: 2)
            }
        }
        .background(slotFrameReporter(slot))
    }

    /// An item in its home cell. `.items` tabs reorder by dragging; `.folder`
    /// items are draggable *out* (to Finder / other apps) as their file URL.
    @ViewBuilder
    private func inCellItem(_ item: DrawerItem) -> some View {
        let cell = itemView(item).opacity(dragging?.id == item.id ? 0.25 : 1)
        if editable {
            cell.gesture(reorderGesture(item))
        } else {
            cell.onDrag { dragProvider(item) }
        }
    }

    @ViewBuilder
    private var draggedOverlay: some View {
        if editable, let dragging, let home = slotFrames[dragging.slot] {
            itemView(dragging)
                .frame(width: home.width, height: home.height)
                .scaleEffect(1.06)
                .opacity(0.95)
                .offset(x: home.minX + dragOffset.width, y: home.minY + dragOffset.height)
                .allowsHitTesting(false)
        }
    }

    private func slotFrameReporter(_ slot: Int) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(key: SlotFramesKey.self, value: [slot: proxy.frame(in: .named(contentSpace))])
        }
    }

    private func reorderGesture(_ item: DrawerItem) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named(contentSpace))
            .onChanged { value in
                if dragging?.id != item.id { dragging = item }
                dragOffset = value.translation
                dropTargetSlot = targetSlot(at: value.location)
            }
            .onEnded { value in
                if let slot = targetSlot(at: value.location), let dragging {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        model.onPlaceItem?(dragging.id, slot)
                    }
                }
                dragging = nil
                dragOffset = .zero
                dropTargetSlot = nil
            }
    }

    private func targetSlot(at point: CGPoint) -> Int? {
        if let hit = slotFrames.first(where: { $0.value.contains(point) })?.key {
            return hit
        }
        return slotFrames.min { squaredDistance($0.value, point) < squaredDistance($1.value, point) }?.key
    }

    private func squaredDistance(_ rect: CGRect, _ point: CGPoint) -> CGFloat {
        let dx = point.x - rect.midX, dy = point.y - rect.midY
        return dx * dx + dy * dy
    }

    private func dragProvider(_ item: DrawerItem) -> NSItemProvider {
        if let url = BookmarkResolver.url(for: item) {
            return NSItemProvider(object: url as NSURL)
        }
        return NSItemProvider()
    }

    private func itemView(_ item: DrawerItem, layout: DrawerLayout? = nil) -> some View {
        ItemView(
            item: item,
            iconSize: CGFloat(preferences.iconSize),
            layout: layout ?? preferences.drawerLayout,
            launchOnSingleClick: preferences.launchOnSingleClick,
            onLaunch: { model.onLaunch?(item) },
            onReveal: { model.onRevealItem?(item) },
            onRemove: editable ? { model.onRemoveItem?(item) } : nil,
            onRename: editable ? { model.onRenameItem?(item) } : nil,
            onChangeIcon: editable ? { model.onChangeItemIcon?(item) } : nil,
            onResetIcon: editable ? { model.onResetItemIcon?(item) } : nil,
            onEmptyTrash: item.kind == .trash ? { model.onEmptyTrash?() } : nil,
            iconNonce: model.iconNonce,
            onEject: item.kind == .disk ? { model.onEjectItem?(item) } : nil,
            onCustomizeIcon: { model.onCustomizeItemIcon?(item) },   // any item, any tab kind
            runningBundleIDs: model.runningBundleIDs
        )
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: emptyIcon)
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text(emptyMessage)
                .foregroundStyle(.secondary)
                .font(.callout)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }

    private var emptyIcon: String {
        switch model.kind {
        case .folder: return "folder"
        case .disks: return "externaldrive"
        case .network: return "externaldrive.connected.to.line.below"
        case .cloud: return "icloud"
        case .recents: return "clock.arrow.circlepath"
        default: return "tray.and.arrow.down"
        }
    }

    private var emptyMessage: String {
        switch model.kind {
        case .folder:
            return model.folderURL == nil
                ? "No folder chosen.\nPick one with the gear above."
                : "This folder is empty."
        case .disks:
            return "No ejectable disks mounted."
        case .network:
            return "No network shares mounted."
        case .cloud:
            return "No cloud drives found."
        case .recents:
            return "Nothing opened from MacDring yet."
        default:
            return "Drag apps & files here"
        }
    }
}

/// Collects each slot's frame (in the drawer content space) so the reorder
/// gesture and the AppKit drag destination can find the slot under a point.
private struct SlotFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
