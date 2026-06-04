import AppKit
import SwiftUI

/// An `NSHostingView` that accepts the first mouse click even when its panel
/// isn't key, so a click on the (background-app) pill registers immediately.
private final class FirstMouseTabHostingView: NSHostingView<TabStripView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Hosts a borderless, non-activating panel for one tab pill: keeps it sized to
/// its SwiftUI content, anchored to its edge, and relays click/hover/drag/drop
/// up to the `TabController`. Non-activating so clicking a tab never steals
/// focus from the user's frontmost app.
final class TabWindowController {

    let tabID: UUID
    let model: TabStripModel

    private let preferences: Preferences
    private let panel: NSPanel
    private let hostingView: FirstMouseTabHostingView

    /// The screen the pill is currently placed on (used to position the drawer).
    private(set) var currentScreen: NSScreen?
    /// The pill's flush-to-edge resting frame (where it sits when its drawer is
    /// closed). The drawer is centered along the edge on this frame.
    private(set) var restingFrame: CGRect = .zero
    private var anchor: ScreenAnchor

    /// The frame we last set deliberately. If the panel's frame diverges from this
    /// while we're not the one changing it, an external agent (a window-management
    /// / tiling tool) grabbed it — so we snap it back. See `defendFrame`.
    private var intendedFrame: CGRect = .zero
    /// Number of in-flight frame animations. A *count* (not a bool) so overlapping
    /// animations — a rapid open/close/switch — don't let the first one's completion
    /// re-arm the frame-defender while a later one is still running. See ANALYSIS.md B8.
    private var frameAdjustmentDepth = 0
    private var frameObservers: [NSObjectProtocol] = []

    // Controller hooks.
    var onTap: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    var onDropURLs: (([URL]) -> Void)?
    var onDragWillBegin: (() -> Void)?
    var onDragChanged: (() -> Void)?
    var onDragEnded: (() -> Void)?

    init(tab: Tab, preferences: Preferences) {
        self.tabID = tab.id
        self.preferences = preferences
        self.anchor = tab.anchor
        self.model = TabStripModel(title: tab.title, colorHex: tab.colorHex, glyph: tab.glyph, edge: tab.anchor.edge)

        let hosting = FirstMouseTabHostingView(rootView: TabStripView(model: model, preferences: preferences))
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.autoresizingMask = [.width, .height]
        self.hostingView = hosting

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 60, height: 60),
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
        panel.isMovable = false   // we position it programmatically; deter window drags
        panel.level = preferences.tabWindowLevel.nsWindowLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let container = NSView(frame: panel.frame)
        container.autoresizesSubviews = true
        hosting.frame = container.bounds
        container.addSubview(hosting)
        panel.contentView = container
        self.panel = panel

        wireModelCallbacks()
        observeExternalFrameChanges()
    }

    deinit {
        frameObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    /// Watch for frame changes we didn't make (e.g. a tiling tool resizing the
    /// pill) and restore the intended frame, so a tab can't be "lost."
    private func observeExternalFrameChanges() {
        let center = NotificationCenter.default
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            let token = center.addObserver(forName: name, object: panel, queue: .main) { [weak self] _ in
                self?.defendFrame()
            }
            frameObservers.append(token)
        }
    }

    private func defendFrame() {
        guard frameAdjustmentDepth == 0, intendedFrame != .zero else { return }
        let current = panel.frame
        let drifted = abs(current.minX - intendedFrame.minX) > 1
            || abs(current.minY - intendedFrame.minY) > 1
            || abs(current.width - intendedFrame.width) > 1
            || abs(current.height - intendedFrame.height) > 1
        guard drifted else { return }
        panel.setFrame(intendedFrame, display: true)   // matches intended now → no further restore
    }

    private func wireModelCallbacks() {
        model.onTap = { [weak self] in self?.onTap?() }
        model.onHoverChanged = { [weak self] inside in self?.onHoverChanged?(inside) }
        model.onDropURLs = { [weak self] urls in self?.onDropURLs?(urls) }
        model.onDragBegan = { [weak self] in self?.onDragWillBegin?() }
        model.onDragChanged = { [weak self] in self?.onDragChanged?() }
        model.onDragEnded = { [weak self] in self?.onDragEnded?() }
    }

    /// The pill's current on-screen frame.
    var frame: CGRect { panel.frame }

    /// The along-edge extent of the pill (its length), used to keep a consistent
    /// size while previewing a snap to a different edge during a drag.
    var contentLength: CGFloat { max(restingFrame.width, restingFrame.height) }

    func update(tab: Tab) {
        anchor = tab.anchor
        model.title = tab.title
        model.colorHex = tab.colorHex
        model.glyph = tab.glyph
        model.edge = tab.anchor.edge
    }

    func setOpen(_ open: Bool) { model.isOpen = open }

    /// Measures the pill content and computes its flush-to-edge resting frame on
    /// `screen`. Moves the panel there unless its drawer is open (in which case
    /// the controller positions it on the drawer's inner face).
    func place(on screen: NSScreen) {
        currentScreen = screen
        panel.level = preferences.tabWindowLevel.nsWindowLevel

        hostingView.layoutSubtreeIfNeeded()
        let fitting = hostingView.fittingSize
        let thickness = CGFloat(preferences.tabThickness)
        let size: CGSize = model.edge.isVertical
            ? CGSize(width: thickness, height: max(fitting.height, thickness))
            : CGSize(width: max(fitting.width, thickness), height: thickness)

        restingFrame = EdgeLayout.tabFrame(edge: model.edge, position: anchor.position, size: size, in: screen.visibleFrame)
        if !model.isOpen {
            applyFrame(restingFrame)
        }
    }

    /// Positions the panel at an explicit frame (e.g. the open position, riding on
    /// the drawer's inner face).
    func applyFrame(_ frame: CGRect) {
        intendedFrame = frame
        panel.setFrame(frame, display: true)
        hostingView.frame = panel.contentView?.bounds ?? NSRect(origin: .zero, size: frame.size)
    }

    /// Returns the pill to its flush-to-edge resting position.
    func restoreResting() { applyFrame(restingFrame) }

    /// Animates the pill to `frame` over `duration` seconds (0 = instant). Used to
    /// slide the tab onto / off the drawer's inner face in sync with the drawer.
    func animate(to frame: CGRect, duration: TimeInterval) {
        guard duration > 0 else { applyFrame(frame); return }
        intendedFrame = frame
        frameAdjustmentDepth += 1   // suppress the frame-defender during the animation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.frameAdjustmentDepth = max(0, self.frameAdjustmentDepth - 1)
            // Only re-sync the hosting view once the last overlapping animation ends.
            if self.frameAdjustmentDepth == 0 {
                self.hostingView.frame = self.panel.contentView?.bounds ?? .zero
            }
        })
    }

    /// Live drag preview: snaps the pill flush to `edge` at fractional `position`
    /// on `screen`, keeping a consistent `length` along the edge. Updates
    /// `model.edge` so the pill reshapes (corners face inward) as it crosses edges.
    func previewSnap(edge: Edge, position: Double, length: CGFloat, on screen: NSScreen) {
        currentScreen = screen
        model.edge = edge
        let thickness = CGFloat(preferences.tabThickness)
        let size: CGSize = edge.isVertical
            ? CGSize(width: thickness, height: max(length, thickness))
            : CGSize(width: max(length, thickness), height: thickness)
        let frame = EdgeLayout.tabFrame(edge: edge, position: position, size: size, in: screen.visibleFrame)
        restingFrame = frame
        applyFrame(frame)
    }

    func show() { panel.orderFrontRegardless() }
    func hide() { panel.orderOut(nil) }

    func close() {
        panel.orderOut(nil)
        panel.contentView = nil
    }
}
