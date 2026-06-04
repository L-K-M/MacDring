import AppKit
import Combine
import UniformTypeIdentifiers

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

    /// Edge-hover monitors (no permission needed — mouse only) that drive
    /// Dock-style auto-hide / auto-fade reveal. Active only while a concealable tab
    /// is shown and no drawer is open. See `refreshConcealment`.
    private var revealMonitorGlobal: Any?
    private var revealMonitorLocal: Any?
    /// Per-tab delayed re-conceal work, so a tab doesn't snap shut the instant the
    /// cursor leaves its reveal zone.
    private var pendingReConceal: [UUID: DispatchWorkItem] = [:]
    /// The tab currently being dragged, excluded from concealment so it can't slide
    /// out from under the cursor mid-drag.
    private var draggingTabID: UUID?
    /// How far past a tab's resting footprint the cursor still counts as "hovering"
    /// it (an easier target than the thin revealed sliver).
    private static let revealSlop: CGFloat = 6
    /// Delay before an idle tab re-conceals after the cursor leaves its zone.
    private static let reConcealDelay: TimeInterval = 0.45
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
        // A preference change reconciles every tab window (re-measure + reposition,
        // and re-list every folder tab). Dragging an appearance slider fires
        // `objectWillChange` continuously, so debounce to coalesce a burst into a
        // single reconcile once the value settles — `objectWillChange` fires *before*
        // the change, and a debounced main-queue delivery reads the updated value.
        preferences.objectWillChange
            .debounce(for: .milliseconds(80), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.reconcile() }
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
            cancelReConceal(id)
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

        deOverlapStackedTabs()
        refreshOpenDrawer()
        refreshConcealment(animated: false)
    }

    /// Spaces tabs that share a display + edge so they don't render on top of each
    /// other. Tabs keep their fractional position unless they'd overlap, in which
    /// case later ones (by `order`, then `position`) are nudged along the edge.
    /// The open tab is left riding on the drawer face; its new resting frame takes
    /// effect when it closes. See PLAN.md §5.
    private func deOverlapStackedTabs() {
        struct Key: Hashable { let screen: Int; let edge: Edge }
        var groups: [Key: [(wc: TabWindowController, tab: Tab)]] = [:]

        for (id, wc) in tabWindows {
            guard wc.isShown,
                  let screen = wc.currentScreen,
                  let number = screenNumber(screen),
                  let tab = store.tab(id: id) else { continue }
            groups[Key(screen: number, edge: tab.anchor.edge), default: []].append((wc, tab))
        }

        for (key, group) in groups where group.count > 1 {
            let sorted = group.sorted {
                ($0.tab.anchor.order, $0.tab.anchor.position, $0.tab.id.uuidString)
                    < ($1.tab.anchor.order, $1.tab.anchor.position, $1.tab.id.uuidString)
            }
            guard let visible = sorted.first?.wc.currentScreen?.visibleFrame else { continue }
            let packed = EdgeLayout.packAlongEdge(frames: sorted.map { $0.wc.restingFrame },
                                                  edge: key.edge, gap: 6, in: visible)
            for (entry, frame) in zip(sorted, packed) { entry.wc.setRestingFrame(frame) }
        }
    }

    private func screenNumber(_ screen: NSScreen) -> Int? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue
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
              // Resolve the tab's screen *live* rather than trusting a possibly-stale
              // `currentScreen`: a parked tab (its display disconnected, default policy)
              // keeps its old screen reference, so a hotkey/spring-open must not slide a
              // drawer out onto a detached display. See ANALYSIS.md B3.
              let screen = resolvedScreen(for: tab) else { return }
        if let prev = openTabID, prev != id {
            tabWindows[prev]?.setOpen(false)
            tabWindows[prev]?.restoreResting()
        }
        cancelHoverClose()
        cancelReConceal(id)
        pendingSpringOpen?.cancel(); pendingSpringOpen = nil
        openTabID = id
        wc.setOpen(true)
        refreshConcealment(animated: false)   // a drawer is open → suspend the edge-hover monitor
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
        refreshConcealment(animated: true)   // drawer closed → resume auto-hide/fade
    }

    /// The screen a tab should currently appear on: its anchored display if present,
    /// or the main display under the move-to-main policy, otherwise `nil` (parked).
    /// Mirrors the placement decision in `reconcile`, so a drawer only opens where
    /// the tab is actually shown.
    private func resolvedScreen(for tab: Tab) -> NSScreen? {
        if let screen = registry.screen(for: tab.anchor.displayUUID) { return screen }
        if preferences.disconnectPolicy == .moveToMain { return NSScreen.main }
        return nil
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

    // MARK: Auto-hide / auto-fade (Dock-style concealment)

    /// Tabs eligible for concealment right now: on screen, with a concealment style,
    /// not the open tab, and not being dragged.
    private func concealableTabs() -> [(id: UUID, wc: TabWindowController)] {
        tabWindows.compactMap { id, wc in
            guard wc.isShown, wc.concealmentStyle != .never,
                  id != openTabID, id != draggingTabID, store.tab(id: id) != nil else { return nil }
            return (id, wc)
        }
    }

    /// Re-evaluates concealment for every concealable tab against the current cursor
    /// and starts/stops the edge-hover monitor. While a drawer is open, concealment
    /// is suspended entirely (the monitor is torn down). `animated` is false for the
    /// instant snap on reconcile/launch and true for live transitions.
    private func refreshConcealment(animated: Bool) {
        guard openTabID == nil else { stopRevealMonitoring(); return }
        let tabs = concealableTabs()
        guard !tabs.isEmpty else { stopRevealMonitoring(); return }
        startRevealMonitoring()
        let mouse = NSEvent.mouseLocation
        for (id, wc) in tabs { applyRevealState(id: id, wc: wc, mouse: mouse, animated: animated) }
    }

    /// Reveals or conceals one tab from the cursor's position relative to its reveal
    /// zone (the resting footprint, widened a little for an easier target).
    private func applyRevealState(id: UUID, wc: TabWindowController, mouse: CGPoint, animated: Bool) {
        let duration = animated ? animationDuration : 0
        if revealZone(for: wc).contains(mouse) {
            cancelReConceal(id)
            wc.reveal(duration: duration)
        } else if wc.isConcealed {
            cancelReConceal(id)   // already hidden — nothing to schedule
        } else if animated {
            scheduleReConceal(id)
        } else {
            cancelReConceal(id)
            wc.conceal(duration: 0)
        }
    }

    /// The screen region whose hover reveals a concealed tab.
    private func revealZone(for wc: TabWindowController) -> CGRect {
        wc.restingFrame.insetBy(dx: -Self.revealSlop, dy: -Self.revealSlop)
    }

    private func scheduleReConceal(_ id: UUID) {
        guard pendingReConceal[id] == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingReConceal[id] = nil
            guard id != self.openTabID, id != self.draggingTabID, let wc = self.tabWindows[id] else { return }
            // Only conceal if the cursor is still away from the tab's zone.
            if !self.revealZone(for: wc).contains(NSEvent.mouseLocation) {
                wc.conceal(duration: self.animationDuration)
            }
        }
        pendingReConceal[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.reConcealDelay, execute: work)
    }

    private func cancelReConceal(_ id: UUID) {
        pendingReConceal[id]?.cancel()
        pendingReConceal[id] = nil
    }

    private func handleRevealMouseMoved() {
        let mouse = NSEvent.mouseLocation
        for (id, wc) in concealableTabs() {
            applyRevealState(id: id, wc: wc, mouse: mouse, animated: true)
        }
    }

    private func startRevealMonitoring() {
        // Mouse-moved monitors need no permission (unlike key monitors / event taps).
        if revealMonitorGlobal == nil {
            revealMonitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
                self?.handleRevealMouseMoved()
            }
        }
        if revealMonitorLocal == nil {
            revealMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
                self?.handleRevealMouseMoved()
                return event
            }
        }
    }

    private func stopRevealMonitoring() {
        if let m = revealMonitorGlobal { NSEvent.removeMonitor(m); revealMonitorGlobal = nil }
        if let m = revealMonitorLocal { NSEvent.removeMonitor(m); revealMonitorLocal = nil }
        pendingReConceal.values.forEach { $0.cancel() }
        pendingReConceal.removeAll()
    }

    // MARK: Drag-to-reposition (snap-to-edge preview)

    private func beginDrag(_ id: UUID) {
        closeDrawer()
        draggingTabID = id
        cancelReConceal(id)
        tabWindows[id]?.reveal(duration: 0)   // a slid-off / faded tab becomes fully grabbable
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
        draggingTabID = nil
        defer { refreshConcealment(animated: true) }   // re-arm auto-hide/fade for the dropped tab
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

    /// Routes files **and web links** dropped on a tab/drawer. `slot` is the drawer
    /// slot they landed on (or -1 for the tab pill / drawer background): dropping on
    /// an **app** opens them with it, on a **folder** files the files into it,
    /// otherwise they are added (items tab) or filed into the mirrored directory
    /// (folder tab). Web links can't be moved on disk, so they're only *added* (and
    /// only on an items tab); they can still be opened-with an app.
    private func handleFileDrop(_ urls: [URL], slot: Int, toTab id: UUID) {
        guard !urls.isEmpty, let tab = store.tab(id: id) else { return }
        let fileURLs = urls.filter { $0.isFileURL }
        let liveItems = tab.kind == .folder ? FolderLister.contents(of: tab) : tab.items
        let target = slot >= 0 ? liveItems.first { $0.slot == slot } : nil

        if let target, target.kind == .application {
            ItemLauncher.open(urls, withApp: target)   // files *or* links → open-with
            return
        }
        if let target, target.kind == .trash {
            FileMover.trash(urls)   // drop onto Trash → move the files to the Trash
            if tab.kind == .folder { refreshOpenDrawer() }
            return
        }
        if let target, target.kind == .folder, let directory = BookmarkResolver.url(for: target) {
            FileMover.move(fileURLs, into: directory)   // only files can be filed in
            if tab.kind == .folder { refreshOpenDrawer() }
            return
        }

        switch tab.kind {
        case .notes:
            return
        case .folder:
            guard let directory = FolderLister.resolveFolder(tab) else { return }
            FileMover.move(fileURLs, into: directory)
            if openTabID == id { refreshOpenDrawer() } else { openDrawer(id) }
        case .items:
            let newItems = urls.map { DrawerItem.fromDroppedURL($0) }   // files & links
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
        drawer.model.onRenameItem = { [weak self] item in self?.renameItem(item) }
        drawer.model.onChangeItemIcon = { [weak self] item in self?.changeItemIcon(item) }
        drawer.model.onResetItemIcon = { [weak self] item in self?.resetItemIcon(item) }
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

    // MARK: Item rename / icon

    /// Renames an item via a small modal prompt, then commits it to the store.
    private func renameItem(_ item: DrawerItem) {
        guard let id = openTabID else { return }
        let alert = NSAlert()
        alert.messageText = "Rename Item"
        alert.informativeText = "Enter a new name for “\(item.displayName)”."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = item.displayName
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)   // a text prompt needs key focus
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var updated = item
        updated.displayName = name
        store.updateItem(updated, inTab: id)
    }

    /// Lets the user pick an image to use as an item's icon, then stores it as a
    /// bookmark so it survives moves/renames.
    private func changeItemIcon(_ item: DrawerItem) {
        guard let id = openTabID else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.message = "Choose an image to use as this item's icon"

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var updated = item
        updated.customIconBookmark = BookmarkResolver.makeBookmark(for: url)
        store.updateItem(updated, inTab: id)
    }

    /// Clears an item's custom icon, restoring its default.
    private func resetItemIcon(_ item: DrawerItem) {
        guard let id = openTabID else { return }
        var updated = item
        updated.customIconBookmark = nil
        store.updateItem(updated, inTab: id)
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
                // Don't steal Esc from one of the app's own ordinary windows
                // (Settings / New Tab); they need it to dismiss sheets, popovers,
                // or fields. The borderless drawer/tab panels aren't `.titled`.
                if let key = NSApp.keyWindow, key.styleMask.contains(.titled) { return event }
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
        stopRevealMonitoring()
        drawer.hide(duration: 0)     // instant on quit, no animation
        openTabID = nil
        for (_, wc) in tabWindows { wc.close() }
        tabWindows.removeAll()
        for (_, entry) in hotkeys { entry.hotkey.unregister() }
        hotkeys.removeAll()
    }
}
