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
    @State private var fileDropSlot: Int?         // external file-drop target

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
    /// Items and folder tabs accept dropped files (routed); notes tabs don't.
    private var acceptsFileDrops: Bool { model.kind != .notes }

    var body: some View {
        let radius = CGFloat(preferences.cornerRadius)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        VStack(alignment: .leading, spacing: 10) {
            header
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
        .onDrop(of: [UTType.fileURL], isTargeted: dropBinding) { providers in
            guard acceptsFileDrops else { return false }
            loadFileURLs(from: providers) { urls in
                if !urls.isEmpty { model.onDropFiles?(urls, -1) }   // -1 = drawer background
            }
            return true
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        switch model.kind {
        case .notes:
            notesEditor
        case .items, .folder:
            if model.items.isEmpty { emptyState } else { content }
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
        TextEditor(text: notesBinding)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.08)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var notesBinding: Binding<String> {
        Binding(get: { model.notes }, set: { model.notes = $0; model.onNotesChanged?($0) })
    }

    // MARK: Items / folder grid

    private var content: some View {
        ScrollView {
            itemsLayout
                .coordinateSpace(name: contentSpace)
                .overlay(alignment: .topLeading) { draggedOverlay }
                .onPreferenceChange(SlotFramesKey.self) { slotFrames = $0 }
        }
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
                    fileDropTarget(
                        inCellItem(item)
                            .padding(.vertical, 3)
                            .padding(.horizontal, 4)
                            .background(slotFrameReporter(item.slot)),
                        slot: item.slot
                    )
                }
            }
        }
    }

    private func gridSlot(_ slot: Int) -> some View {
        let item = model.item(atSlot: slot)
        let highlighted = (dropTargetSlot == slot && dragging?.slot != slot) || fileDropSlot == slot
        return fileDropTarget(
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white.opacity(highlighted ? 0.16 : 0))
                if let item { inCellItem(item) }
            }
            .frame(maxWidth: .infinity)
            .frame(height: cellHeight)
            .background(slotFrameReporter(slot)),
            slot: slot
        )
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

    /// Wraps a cell so a file dragged from elsewhere can be dropped on it.
    private func fileDropTarget(_ view: some View, slot: Int) -> some View {
        view.onDrop(of: [UTType.fileURL], isTargeted: fileDropBinding(slot)) { providers in
            guard acceptsFileDrops else { return false }
            loadFileURLs(from: providers) { urls in
                if !urls.isEmpty { model.onDropFiles?(urls, slot) }
            }
            return true
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

    private func itemView(_ item: DrawerItem) -> some View {
        ItemView(
            item: item,
            iconSize: CGFloat(preferences.iconSize),
            layout: preferences.drawerLayout,
            launchOnSingleClick: preferences.launchOnSingleClick,
            onLaunch: { model.onLaunch?(item) },
            onReveal: { model.onRevealItem?(item) },
            onRemove: editable ? { model.onRemoveItem?(item) } : nil
        )
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: model.kind == .folder ? "folder" : "tray.and.arrow.down")
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

    private var emptyMessage: String {
        if model.kind == .folder {
            return model.folderURL == nil
                ? "No folder chosen.\nPick one with the gear above."
                : "This folder is empty."
        }
        return "Drag apps & files here"
    }

    // MARK: Drop highlight bindings

    private var dropBinding: Binding<Bool> {
        Binding(get: { model.isDropTargeted }, set: { model.isDropTargeted = acceptsFileDrops && $0 })
    }

    private func fileDropBinding(_ slot: Int) -> Binding<Bool> {
        Binding(
            get: { fileDropSlot == slot },
            set: { fileDropSlot = $0 ? slot : (fileDropSlot == slot ? nil : fileDropSlot) }
        )
    }
}

/// Collects each slot's frame (in the drawer content space) so the reorder
/// gesture can find the slot under the cursor.
private struct SlotFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
