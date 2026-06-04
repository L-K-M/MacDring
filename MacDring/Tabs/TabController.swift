import AppKit
import Combine

/// The orchestrator. Reconciles the stored tabs against the live display set
/// into on-screen tab windows, owns the shared drawer, and routes every
/// interaction (click, hover, drag-to-reposition, drop, hotkey, launch).
final class TabController {

    private let store: TabStore
    private let preferences: Preferences
    private let registry: DisplayRegistry
    private let drawer: DrawerWindowController

    private var tabWindows: [UUID: TabWindowController] = [:]
    private var hotkeys: [UUID: (hotkey: CarbonHotkey, spec: HotkeySpec)] = [:]
    private var openTabID: UUID?
    private var hotkeyCounter: UInt32 = 1

    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?
    private var pendingHoverClose: DispatchWorkItem?
    private var pendingSpringOpen: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    /// The pill's along-edge length captured at drag start, kept constant while
    /// previewing snaps to different edges.
    private var dragLength: CGFloat = 60
    /// Whether the tab currently being dragged is locked (won't move).
    private var dragLocked = false

    /// Invoked to open Settings for a tab (the tab's context menu or the drawer's
    /// gear). `nil` opens Settings without selecting a tab. Wired by `AppDelegate`.
    var onOpenSettings: ((UUID?) -> Void)?

    init(store: TabStore, preferences: Preferences, registry: DisplayRegistry) {
        self.store = store
        self.preferences = preferences
        self.registry = registry
        self.drawer = DrawerWindowController(preferences: preferences)

        wireDrawer()
        store.onChange = { [weak self] in self?.reconcile() }
        registry.onChange = { [weak self] in self?.reconcile() }
        preferences.objectWillChange
            .sink { [weak self] in DispatchQueue.main.async { self?.reconcile() } }
            .store(in: &cancellables)
    }

    func start() { reconcile() }

    // MARK: Reconcile

    /// Brings the on-screen windows in line with the stored tabs and the current
    /// displays. Called on every store change, display change, and appearance
    /// change. See PLAN.md §6 for the park-vs-move-to-main policy.
    func reconcile() {
        let tabs = store.tabs
        let liveIDs = Set(tabs.map(\.id))

        for (id, wc) in tabWindows where !liveIDs.contains(id) {
            wc.close()
            tabWindows[id] = nil
            unregisterHotkey(id)
            if openTabID == id { closeDrawer() }
        }

        for tab in tabs {
            let wc = tabWindows[tab.id] ?? makeWindow(for: tab)
            tabWindows[tab.id] = wc
            wc.update(tab: tab)

            if let screen = registry.screen(for: tab.anchor.displayUUID) {
                wc.place(on: screen)
                wc.show()
            } else if preferences.disconnectPolicy == .moveToMain, let main = NSScreen.main {
                wc.place(on: main)
                wc.show()
            } else {
                wc.hide()                      // park until the display returns
                if openTabID == tab.id { closeDrawer() }
            }
            registerHotkeyIfNeeded(for: tab)
        }

        refreshOpenDrawer()
    }

    private func refreshOpenDrawer() {
        guard let id = openTabID,
              let wc = tabWindows[id],
              let tab = store.tab(id: id),
              let screen = wc.currentScreen else { return }
        drawer.refresh(tab: tab, tabFrame: wc.restingFrame, edge: tab.anchor.edge, on: screen)
        wc.applyFrame(EdgeLayout.openedTabFrame(edge: tab.anchor.edge,
                                                restingTabFrame: wc.restingFrame,
                                                drawerFrame: drawer.openFrame))
    }

    private func makeWindow(for tab: Tab) -> TabWindowController {
        let wc = TabWindowController(tab: tab, preferences: preferences)
        let id = tab.id
        wc.onTap = { [weak self] in self?.toggleDrawer(id) }
        wc.onHoverChanged = { [weak self] inside in self?.handleHover(id, inside: inside) }
        wc.onDropURLs = { [weak self] urls in self?.handleFileDrop(urls, slot: -1, toTab: id) }
        wc.model.onDragHover = { [weak self] targeted in self?.handleDragHover(id, targeted: targeted) }
        wc.onDragWillBegin = { [weak self] in self?.beginDrag(id) }
        wc.onDragChanged = { [weak self] in self?.previewDrag(id) }
        wc.onDragEnded = { [weak self] in self?.endDrag(id) }
        wc.model.onRequestSettings = { [weak self] in self?.onOpenSettings?(id) }
        wc.model.onDelete = { [weak self] in self?.store.removeTab(id: id) }
        wc.model.onMoveToEdge = { [weak self] edge in self?.moveTab(id, toEdge: edge) }
        return wc
    }

    /// Re-anchors a tab to a different edge (pill context menu), keeping its
    /// display, fractional position, and stack order.
    private func moveTab(_ id: UUID, toEdge edge: Edge) {
        guard let tab = store.tab(id: id), tab.anchor.edge != edge else { return }
        var anchor = tab.anchor
        anchor.edge = edge
        store.setAnchor(anchor, forTab: id)
    }

    // MARK: Drawer open / close

    private func toggleDrawer(_ id: UUID) {
        if openTabID == id { closeDrawer() } else { openDrawer(id) }
    }

    private func openDrawer(_ id: UUID) {
        guard let wc = tabWindows[id],
              let tab = store.tab(id: id),
              let screen = wc.currentScreen else { return }
        if let prev = openTabID, prev != id {
            tabWindows[prev]?.setOpen(false)
            tabWindows[prev]?.restoreResting()
        }
        cancelHoverClose()
        pendingSpringOpen?.cancel(); pendingSpringOpen = nil
        openTabID = id
        wc.setOpen(true)
        let duration = animationDuration
        // The drawer slides out flush against the screen edge (centered on the
        // tab's resting position); the tab slides onto the drawer's inner face.
        drawer.show(tab: tab, tabFrame: wc.restingFrame, edge: tab.anchor.edge, on: screen, duration: duration)
        let openedTab = EdgeLayout.openedTabFrame(edge: tab.anchor.edge,
                                                  restingTabFrame: wc.restingFrame,
                                                  drawerFrame: drawer.openFrame)
        wc.animate(to: openedTab, duration: duration)
        startMonitoring()
    }

    private func closeDrawer() {
        cancelHoverClose()
        pendingSpringOpen?.cancel(); pendingSpringOpen = nil
        let duration = animationDuration
        if let id = openTabID, let wc = tabWindows[id] {
            wc.setOpen(false)
            wc.animate(to: wc.restingFrame, duration: duration)   // slide the tab back to the edge
        }
        openTabID = nil
        drawer.hide(duration: duration)
        stopMonitoring()
    }

    /// Drawer open/close animation duration; 0 when *Reduce Motion* is on.
    private var animationDuration: TimeInterval {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return 0 }
        return max(0, preferences.animationMs / 1000.0)
    }

    // MARK: Hover (hover-to-open tabs)

    private func handleHover(_ id: UUID, inside: Bool) {
        guard let tab = store.tab(id: id), tab.behavior.openOnHover else { return }
        if inside {
            cancelHoverClose()
            openDrawer(id)
        } else {
            scheduleHoverClose()
        }
    }

    private func scheduleHoverClose() {
        pendingHoverClose?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.closeDrawer() }
        pendingHoverClose = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func cancelHoverClose() {
        pendingHoverClose?.cancel()
        pendingHoverClose = nil
    }

    // MARK: Drag-to-reposition (snap-to-edge preview)

    private func beginDrag(_ id: UUID) {
        closeDrawer()
        dragLocked = store.tab(id: id)?.locked ?? false
        if let wc = tabWindows[id] { dragLength = wc.contentLength }
    }

    /// Live preview while dragging: the pill stays attached to the nearest edge
    /// and slides along it to the cursor, reshaping as it crosses to a new edge.
    /// A locked tab doesn't move.
    private func previewDrag(_ id: UUID) {
        guard !dragLocked, let wc = tabWindows[id], let target = dragTarget() else { return }
        wc.previewSnap(edge: target.edge, position: target.position, length: dragLength, on: target.screen)
    }

    /// Commit the snapped anchor on release; `reconcile` then re-measures and
    /// places the pill precisely. A locked tab doesn't move.
    private func endDrag(_ id: UUID) {
        guard !dragLocked else { return }
        guard let target = dragTarget(), let uuid = registry.uuid(for: target.screen) else { return }
        let order = store.tab(id: id)?.anchor.order ?? 0
        store.setAnchor(ScreenAnchor(displayUUID: uuid, edge: target.edge, position: target.position, order: order), forTab: id)
    }

    /// The screen / edge / position the dragged pill should snap to, from the
    /// current global cursor location.
    private func dragTarget() -> (screen: NSScreen, edge: Edge, position: Double)? {
        let mouse = NSEvent.mouseLocation
        guard let screen = screenContaining(mouse) else { return nil }
        let visible = screen.visibleFrame
        let edge = nearestEdge(to: mouse, in: visible)
        let position = EdgeLayout.position(forPoint: mouse, edge: edge, in: visible)
        return (screen, edge, position)
    }

    private func screenContaining(_ point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
            ?? NSScreen.screens.min { squaredDistance($0.frame, point) < squaredDistance($1.frame, point) }
    }

    private func nearestEdge(to p: CGPoint, in vf: CGRect) -> Edge {
        let distances: [(Edge, CGFloat)] = [
            (.left, abs(p.x - vf.minX)),
            (.right, abs(vf.maxX - p.x)),
            (.top, abs(vf.maxY - p.y)),
            (.bottom, abs(p.y - vf.minY)),
        ]
        return distances.min { $0.1 < $1.1 }?.0 ?? .right
    }

    private func squaredDistance(_ rect: CGRect, _ p: CGPoint) -> CGFloat {
        let dx = p.x - rect.midX, dy = p.y - rect.midY
        return dx * dx + dy * dy
    }

    // MARK: File drops & spring-loading

    /// Routes files dropped on a tab/drawer. `slot` is the drawer slot they landed
    /// on (or -1 for the tab pill / drawer background): dropping on an **app**
    /// opens the files with it, on a **folder** files them into it, otherwise they
    /// are added (items tab) or filed into the mirrored directory (folder tab).
    private func handleFileDrop(_ urls: [URL], slot: Int, toTab id: UUID) {
        guard !urls.isEmpty, let tab = store.tab(id: id) else { return }
        let liveItems = tab.kind == .folder ? FolderLister.contents(of: tab) : tab.items
        let target = slot >= 0 ? liveItems.first { $0.slot == slot } : nil

        if let target, target.kind == .application {
            ItemLauncher.open(urls, withApp: target)
            return
        }
        if let target, target.kind == .trash {
            FileMover.trash(urls)   // drop onto Trash → move the files to the Trash
            if tab.kind == .folder { refreshOpenDrawer() }
            return
        }
        if let target, target.kind == .folder, let directory = BookmarkResolver.url(for: target) {
            FileMover.move(urls, into: directory)
            if tab.kind == .folder { refreshOpenDrawer() }
            return
        }

        switch tab.kind {
        case .notes:
            return
        case .folder:
            guard let directory = FolderLister.resolveFolder(tab) else { return }
            FileMover.move(urls, into: directory)
            if openTabID == id { refreshOpenDrawer() } else { openDrawer(id) }
        case .items:
            let newItems = urls.map { DrawerItem.fromFileURL($0) }
            for item in newItems { store.addItem(item, toTab: id) }
            if slot >= 0, let first = newItems.first {
                store.placeItem(first.id, atSlot: slot, inTab: id)   // drop into the targeted empty slot
            }
            if openTabID != id { openDrawer(id) }   // a store change already refreshed an open drawer
        }
    }

    /// Spring-loads a tab: hovering it with a file drag opens its drawer after a
    /// short delay, so the file can be dropped onto the drawer's contents.
    private func handleDragHover(_ id: UUID, targeted: Bool) {
        guard targeted else { pendingSpringOpen?.cancel(); pendingSpringOpen = nil; return }
        guard openTabID != id else { return }
        pendingSpringOpen?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.openDrawer(id) }
        pendingSpringOpen = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    // MARK: Hotkeys

    private func registerHotkeyIfNeeded(for tab: Tab) {
        guard let spec = tab.hotkey, KeyCodes.hasModifier(spec.carbonModifiers) else {
            unregisterHotkey(tab.id)
            return
        }
        if let existing = hotkeys[tab.id], existing.spec == spec { return }
        unregisterHotkey(tab.id)

        let hotkey = CarbonHotkey(identifier: hotkeyCounter)
        hotkeyCounter += 1
        let id = tab.id
        hotkey.onPressed = { [weak self] in self?.toggleDrawer(id) }
        if hotkey.register(keyCode: spec.keyCode, modifiers: spec.carbonModifiers) {
            hotkeys[tab.id] = (hotkey, spec)
        }
    }

    private func unregisterHotkey(_ id: UUID) {
        hotkeys[id]?.hotkey.unregister()
        hotkeys[id] = nil
    }

    // MARK: Drawer wiring & launching

    private func wireDrawer() {
        drawer.model.onLaunch = { [weak self] item in self?.launch(item) }
        drawer.model.onRemoveItem = { [weak self] item in
            guard let self, let id = self.openTabID else { return }
            self.store.removeItem(id: item.id, fromTab: id)
        }
        drawer.model.onRevealItem = { item in ItemLauncher.revealInFinder(item) }
        drawer.model.onDropFiles = { [weak self] urls, slot in
            guard let self, let id = self.openTabID else { return }
            self.handleFileDrop(urls, slot: slot, toTab: id)
        }
        drawer.model.onMouseEntered = { [weak self] in self?.cancelHoverClose() }
        drawer.model.onMouseExited = { [weak self] in
            guard let self, let id = self.openTabID, let tab = self.store.tab(id: id) else { return }
            if tab.behavior.openOnHover { self.scheduleHoverClose() }
        }
        drawer.model.onPlaceItem = { [weak self] itemID, slot in
            guard let self, let id = self.openTabID else { return }
            self.store.placeItem(itemID, atSlot: slot, inTab: id)
        }
        drawer.model.onOpenSettings = { [weak self] in
            guard let self, let id = self.openTabID else { return }
            self.closeDrawer()
            self.onOpenSettings?(id)
        }
        drawer.model.onToggleLocked = { [weak self] in
            guard let self, let id = self.openTabID else { return }
            let locked = self.store.tab(id: id)?.locked ?? false
            self.store.setLocked(!locked, forTab: id)
        }
        drawer.model.onNotesChanged = { [weak self] text in
            guard let self, let id = self.openTabID else { return }
            self.store.setNotes(text, forTab: id)
        }
        drawer.model.onOpenFolder = { [weak self] in
            guard let self, let id = self.openTabID, let tab = self.store.tab(id: id),
                  let url = FolderLister.resolveFolder(tab) else { return }
            NSWorkspace.shared.open(url)
        }
    }

    private func launch(_ item: DrawerItem) {
        ItemLauncher.launch(item)
        let keepOpen = openTabID.flatMap { store.tab(id: $0) }?.behavior.keepOpenAfterLaunch ?? false
        if !keepOpen { closeDrawer() }
    }

    // MARK: Dismissal monitoring

    private func startMonitoring() {
        stopMonitoring()
        // Mouse-down in another app closes the drawer (unless the tab is pinned).
        // Global *mouse* monitors need no permission; we only watch keys locally.
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                guard let id = self.openTabID, let tab = self.store.tab(id: id) else {
                    self.closeDrawer()
                    return
                }
                if tab.behavior.autoHide { self.closeDrawer() }
            }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 {   // Escape
                self?.closeDrawer()
                return nil
            }
            return event
        }
    }

    private func stopMonitoring() {
        if let m = globalClickMonitor { NSEvent.removeMonitor(m); globalClickMonitor = nil }
        if let m = localKeyMonitor { NSEvent.removeMonitor(m); localKeyMonitor = nil }
    }

    // MARK: Lifecycle

    /// Persists immediately and tears down all windows/hotkeys (called on quit).
    func saveAndTeardown() {
        store.saveNow()
        stopMonitoring()
        drawer.hide(duration: 0)     // instant on quit, no animation
        openTabID = nil
        for (_, wc) in tabWindows { wc.close() }
        tabWindows.removeAll()
        for (_, entry) in hotkeys { entry.hotkey.unregister() }
        hotkeys.removeAll()
    }
}
