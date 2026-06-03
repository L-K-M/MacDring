import AppKit
import SwiftUI

/// The drawer's hosting view, which also serves as the AppKit **drag destination**
/// for file drops. SwiftUI's `.onDrop` is unreliable inside this borderless panel
/// (especially nested in a `ScrollView`) and gives no hovered location — the same
/// reason reordering uses a `DragGesture` instead. So drops are handled here at the
/// AppKit level: the drag location is mapped to a grid slot via `model.slotFrames`
/// (which the SwiftUI content reports in this view's coordinate space) and routed
/// through `model.onDropFiles`. Also accepts the first mouse click while non-key.
private final class DrawerHostingView: NSHostingView<DrawerView> {
    /// Wired by the controller right after construction (the same model the
    /// SwiftUI `DrawerView` observes), used to read slot frames + the tab kind and
    /// to route drops. The controller also calls `registerForDraggedTypes`.
    var model: DrawerModel?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The grid slot under a window-space drag `location` (nearest if none contains
    /// it). Converts to this view's top-left coordinate space to match the frames
    /// the SwiftUI content reports into `model.slotFrames`.
    private func slot(at location: NSPoint, _ model: DrawerModel) -> Int? {
        var p = convert(location, from: nil)            // window → this view
        if !isFlipped { p.y = bounds.height - p.y }      // normalize to top-left (SwiftUI)
        let point = CGPoint(x: p.x, y: p.y)
        let frames = model.slotFrames
        guard !frames.isEmpty else { return nil }
        if let hit = frames.first(where: { $0.value.contains(point) })?.key { return hit }
        // Only snap to the nearest slot when within (or just outside) the grid; a
        // drop on the header/margins returns nil → slot -1 (generic add to the tab),
        // so it can't accidentally land "inside" the nearest folder.
        let grid = frames.values.reduce(CGRect.null) { $0.union($1) }.insetBy(dx: -24, dy: -24)
        guard grid.contains(point) else { return nil }
        return frames.min { sqDist($0.value, point) < sqDist($1.value, point) }?.key
    }

    private func sqDist(_ r: CGRect, _ p: CGPoint) -> CGFloat {
        let dx = p.x - r.midX, dy = p.y - r.midY
        return dx * dx + dy * dy
    }

    /// The model iff this drag is acceptable here (items/folder tab + has file URLs).
    private func droppableModel(_ sender: NSDraggingInfo) -> DrawerModel? {
        guard let model, model.kind != .notes,
              sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self],
                                                      options: [.urlReadingFileURLsOnly: true])
        else { return nil }
        return model
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { updateDrag(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { updateDrag(sender) }

    private func updateDrag(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let model = droppableModel(sender) else { return [] }
        model.fileDropSlot = slot(at: sender.draggingLocation, model)   // drives the per-slot highlight
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { model?.fileDropSlot = nil }
    override func draggingEnded(_ sender: NSDraggingInfo) { model?.fileDropSlot = nil }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        droppableModel(sender) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let model = droppableModel(sender) else { return false }
        let target = slot(at: sender.draggingLocation, model) ?? -1
        let urls = (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                          options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        model.fileDropSlot = nil
        guard !urls.isEmpty else { return false }
        model.onDropFiles?(urls, target)   // routed by TabController (open-with / move-in / add)
        return true
    }
}

/// A borderless panel that is still allowed to become key. Becoming key (while
/// staying a non-activating panel, so the *app* never activates) is what lets
/// SwiftUI drag-to-reorder and the Esc key work inside the drawer.
private final class KeyableDrawerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Owns the single shared drawer panel, positions it adjacent to whichever tab
/// is open (growing away from the edge), and keeps it sized to its content.
/// Non-activating so it never steals focus from the user's frontmost app.
final class DrawerWindowController {

    let model = DrawerModel()
    private let preferences: Preferences
    private let panel: NSPanel
    private let hostingView: DrawerHostingView

    private(set) var isVisible = false
    /// The drawer's fully-open (flush-to-edge) frame for the current tab. The tab
    /// is positioned against this, and the slide animation runs to/from it.
    private(set) var openFrame: CGRect = .zero
    private var currentEdge: Edge = .right
    private var currentScreen: NSScreen?
    private var currentTabFrame: CGRect = .zero

    init(preferences: Preferences) {
        self.preferences = preferences

        let hosting = DrawerHostingView(rootView: DrawerView(model: model, preferences: preferences))
        hosting.model = model
        hosting.registerForDraggedTypes([.fileURL])
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.autoresizingMask = [.width, .height]
        self.hostingView = hosting

        let panel = KeyableDrawerPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.level = .popUpMenu   // above the tab pills
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let container = NSView(frame: panel.frame)
        container.autoresizesSubviews = true
        hosting.frame = container.bounds
        container.addSubview(hosting)
        panel.contentView = container
        self.panel = panel
    }

    /// The drawer's window — used by the controller to test click-outside hits.
    var window: NSWindow { panel }
    var frame: CGRect { panel.frame }

    // MARK: Presentation

    /// How far the drawer nudges (inward) while fading in/out.
    private static let nudge: CGFloat = 22

    /// Shows the drawer for `tab` over `duration` seconds (0 = instant) with a fade
    /// + small inward slide. The slide stays on the drawer's own screen, so it
    /// never bleeds onto an adjacent display at a shared edge.
    func show(tab: Tab, tabFrame: CGRect, edge: Edge, on screen: NSScreen, duration: TimeInterval) {
        apply(tab: tab)
        model.edge = edge
        currentEdge = edge
        currentScreen = screen
        currentTabFrame = tabFrame
        openFrame = computeOpenFrame(in: screen.visibleFrame)

        if duration > 0 {
            panel.setFrame(EdgeLayout.nudgedDrawerFrame(edge: edge, openFrame: openFrame, by: Self.nudge), display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            panel.makeKey()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(openFrame, display: true)
                panel.animator().alphaValue = 1
            }
        } else {
            panel.alphaValue = 1
            panel.setFrame(openFrame, display: true)
            panel.orderFrontRegardless()
            panel.makeKey()
        }
        isVisible = true
    }

    /// Refreshes content for the currently shown tab (e.g. after a drop / reorder)
    /// and re-positions instantly (no animation). Live note text is preserved: a
    /// refresh can be triggered by an *unrelated* reconcile (a screen or preference
    /// change, or a mutation to another tab) while the user is typing, and the model
    /// is the freshest source for an open notes drawer — overwriting it would reset
    /// the editor's selection / in-flight input. See ANALYSIS.md B7.
    func refresh(tab: Tab, tabFrame: CGRect, edge: Edge, on screen: NSScreen) {
        guard isVisible else { return }
        apply(tab: tab, preserveLiveNotes: true)
        model.edge = edge
        currentEdge = edge
        currentScreen = screen
        currentTabFrame = tabFrame
        openFrame = computeOpenFrame(in: screen.visibleFrame)
        panel.setFrame(openFrame, display: true)
    }

    /// Hides the drawer over `duration` seconds with a fade + small inward slide.
    func hide(duration: TimeInterval) {
        guard isVisible else { return }
        isVisible = false
        guard duration > 0 else {
            panel.orderOut(nil)
            panel.alphaValue = 1
            model.items = []
            return
        }
        let end = EdgeLayout.nudgedDrawerFrame(edge: currentEdge, openFrame: openFrame, by: Self.nudge)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(end, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // Skip if a new open happened during the close animation.
            guard let self, !self.isVisible else { return }
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1   // reset while hidden, ready for next open
            self.model.items = []
        })
    }

    /// Loads `tab` into the model. When `preserveLiveNotes` is true (a refresh of an
    /// already-open drawer), a notes tab's live `model.notes` is left untouched so a
    /// background reconcile can't clobber what the user is typing.
    private func apply(tab: Tab, preserveLiveNotes: Bool = false) {
        model.fileDropSlot = nil
        model.slotFrames = [:]
        model.title = tab.title
        model.colorHex = tab.colorHex
        model.columns = max(1, tab.gridColumns)
        model.rows = max(1, tab.gridRows)
        model.locked = tab.locked
        model.kind = tab.kind
        switch tab.kind {
        case .items:
            model.items = tab.items
            model.notes = ""
            model.folderURL = nil
        case .folder:
            model.items = FolderLister.contents(of: tab)   // live directory listing
            model.notes = ""
            model.folderURL = FolderLister.resolveFolder(tab)
        case .notes:
            model.items = []
            if !preserveLiveNotes { model.notes = tab.notes }
            model.folderURL = nil
        }
    }

    /// The drawer's flush-to-edge open frame, sized deterministically from the
    /// item count + appearance (not SwiftUI `fittingSize`, which is unreliable for
    /// a ScrollView/LazyVGrid). `DrawerView` fills it.
    private func computeOpenFrame(in visibleFrame: CGRect) -> CGRect {
        let size: CGSize
        if model.kind == .notes {
            size = DrawerMetrics.notesSize(columns: model.columns, rows: model.rows,
                                           iconSize: CGFloat(preferences.iconSize), in: visibleFrame)
        } else {
            size = DrawerMetrics.contentSize(
                itemCount: model.items.count,
                maxSlot: model.items.map(\.slot).max() ?? -1,
                configuredRows: model.rows,
                layout: preferences.drawerLayout,
                iconSize: CGFloat(preferences.iconSize),
                columns: model.columns,
                in: visibleFrame
            )
        }
        return EdgeLayout.openDrawerFrame(edge: currentEdge, tabFrame: currentTabFrame, contentSize: size, in: visibleFrame)
    }
}
