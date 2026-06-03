import SwiftUI
import UniformTypeIdentifiers

/// The panel that expands from a tab: a header in the tab's color and the tab's
/// items in a grid (or list). The grid is sized by the tab (`columns` x `rows`),
/// and items hold explicit grid **slots**, so they can be arranged freely with
/// gaps — every slot is a drop target.
///
/// Reorder uses a `DragGesture` (SwiftUI's `.onDrop` doesn't fire inside a
/// borderless panel). The dragged item stays dimmed in its home cell while a
/// **copy is drawn in an overlay above the grid** that follows the cursor — this
/// keeps it on top (a per-cell `zIndex` is ignored inside a `LazyVGrid`).
struct DrawerView: View {
    @ObservedObject var model: DrawerModel
    @ObservedObject var preferences: Preferences

    @State private var dragging: DrawerItem?
    @State private var dragOffset: CGSize = .zero
    @State private var slotFrames: [Int: CGRect] = [:]
    @State private var dropTargetSlot: Int?

    private let contentSpace = "macdring.drawer.content"
    private var columns: Int { max(1, model.columns) }
    private var maxSlot: Int { model.items.map(\.slot).max() ?? -1 }
    private var rows: Int {
        DrawerMetrics.gridRowCount(configuredRows: model.rows, maxSlot: maxSlot,
                                   itemCount: model.items.count, columns: columns)
    }
    private var cellHeight: CGFloat { CGFloat(preferences.iconSize) + 26 }

    var body: some View {
        let radius = CGFloat(preferences.cornerRadius)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        VStack(alignment: .leading, spacing: 10) {
            header
            if model.items.isEmpty {
                emptyState
            } else {
                content
            }
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
            loadFileURLs(from: providers) { urls in
                if !urls.isEmpty { model.onDropURLs?(urls) }
            }
            return true
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hexString: model.colorHex))
                .frame(width: 10, height: 10)
            Text(model.title.isEmpty ? "Drawer" : model.title)
                .font(.headline)
            Spacer(minLength: 12)
            Text("\(model.items.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                model.onToggleLocked?()
            } label: {
                Image(systemName: model.locked ? "lock.fill" : "lock.open")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(model.locked ? "Unlock this tab's position" : "Lock this tab's position")
            Button {
                model.onOpenSettings?()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Configure Tab…")
        }
    }

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
                    inCellItem(item)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 4)
                        .background(slotFrameReporter(item.slot))
                }
            }
        }
    }

    /// One grid cell for `slot` — the item placed there, or an empty droppable cell.
    private func gridSlot(_ slot: Int) -> some View {
        let item = model.item(atSlot: slot)
        return ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(dropTargetSlot == slot && dragging?.slot != slot ? 0.16 : 0))
            if let item { inCellItem(item) }
        }
        .frame(maxWidth: .infinity)
        .frame(height: cellHeight)
        .background(slotFrameReporter(slot))
    }

    /// The item in its home cell. While being dragged it's dimmed in place; the
    /// moving copy is rendered by `draggedOverlay` above the grid.
    private func inCellItem(_ item: DrawerItem) -> some View {
        itemView(item)
            .opacity(dragging?.id == item.id ? 0.25 : 1)
            .gesture(reorderGesture(item))
    }

    /// The dragged item, drawn above the whole grid so it's never occluded.
    @ViewBuilder
    private var draggedOverlay: some View {
        if let dragging, let home = slotFrames[dragging.slot] {
            itemView(dragging)
                .frame(width: home.width, height: home.height)
                .scaleEffect(1.06)
                .opacity(0.95)
                .offset(x: home.minX + dragOffset.width, y: home.minY + dragOffset.height)
                .allowsHitTesting(false)
        }
    }

    /// Reports a slot's (or list row's) frame so the drop can find the slot under
    /// the cursor. Frames are fixed cell positions — the dragged copy lives in the
    /// overlay, so nothing moves these.
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

    /// The slot the cursor is over: the slot whose frame contains `point`, else
    /// the nearest slot center.
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

    private func itemView(_ item: DrawerItem) -> some View {
        ItemView(
            item: item,
            iconSize: CGFloat(preferences.iconSize),
            layout: preferences.drawerLayout,
            launchOnSingleClick: preferences.launchOnSingleClick,
            onLaunch: { model.onLaunch?(item) },
            onRemove: { model.onRemoveItem?(item) },
            onReveal: { model.onRevealItem?(item) }
        )
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text("Drag apps & files here")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }

    private var dropBinding: Binding<Bool> {
        Binding(get: { model.isDropTargeted }, set: { model.isDropTargeted = $0 })
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
