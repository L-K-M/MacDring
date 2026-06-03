import AppKit
import SwiftUI

/// An `NSHostingView` that accepts the first mouse click even when its panel
/// isn't key, so the first click on a drawer item registers immediately.
private final class FirstMouseDrawerHostingView: NSHostingView<DrawerView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
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
    private let hostingView: FirstMouseDrawerHostingView

    private(set) var isVisible = false
    /// The drawer's fully-open (flush-to-edge) frame for the current tab. The tab
    /// is positioned against this, and the slide animation runs to/from it.
    private(set) var openFrame: CGRect = .zero
    private var currentEdge: Edge = .right
    private var currentScreen: NSScreen?
    private var currentTabFrame: CGRect = .zero

    init(preferences: Preferences) {
        self.preferences = preferences

        let hosting = FirstMouseDrawerHostingView(rootView: DrawerView(model: model, preferences: preferences))
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
    /// and re-positions instantly (no animation).
    func refresh(tab: Tab, tabFrame: CGRect, edge: Edge, on screen: NSScreen) {
        guard isVisible else { return }
        apply(tab: tab)
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

    private func apply(tab: Tab) {
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
            model.notes = tab.notes
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
