import CoreGraphics

/// Pure geometry: turns a tab's `ScreenAnchor` into on-screen frames, positions
/// a drawer adjacent to its tab, and inverts a drag point back into a fractional
/// position. All coordinates are AppKit/Cocoa screen coordinates (origin
/// bottom-left, y grows upward). No global state, so it's fully unit-testable.
/// See PLAN.md §5–6.
enum EdgeLayout {

    /// Gap between a tab pill and its drawer.
    static let drawerGap: CGFloat = 8

    // MARK: Tab placement

    /// Frame for a tab pill of `size`, anchored to `edge` at fractional
    /// `position` within `visibleFrame`.
    static func tabFrame(edge: Edge, position: Double, size: CGSize, in visibleFrame: CGRect) -> CGRect {
        let p = CGFloat(ScreenAnchor.clampPosition(position))
        switch edge {
        case .left:
            return CGRect(x: visibleFrame.minX,
                          y: yForVertical(position: p, height: size.height, in: visibleFrame),
                          width: size.width, height: size.height)
        case .right:
            return CGRect(x: visibleFrame.maxX - size.width,
                          y: yForVertical(position: p, height: size.height, in: visibleFrame),
                          width: size.width, height: size.height)
        case .top:
            return CGRect(x: xForHorizontal(position: p, width: size.width, in: visibleFrame),
                          y: visibleFrame.maxY - size.height,
                          width: size.width, height: size.height)
        case .bottom:
            return CGRect(x: xForHorizontal(position: p, width: size.width, in: visibleFrame),
                          y: visibleFrame.minY,
                          width: size.width, height: size.height)
        }
    }

    /// For left/right edges: `position` 0 = top, 1 = bottom. Returns the origin
    /// (bottom) y for a window of `height`, clamped within `visibleFrame`.
    private static func yForVertical(position p: CGFloat, height: CGFloat, in vf: CGRect) -> CGFloat {
        let centerY = vf.maxY - p * vf.height
        return clamp(centerY - height / 2, vf.minY, vf.maxY - height)
    }

    /// For top/bottom edges: `position` 0 = leading (left), 1 = trailing (right).
    private static func xForHorizontal(position p: CGFloat, width: CGFloat, in vf: CGRect) -> CGFloat {
        let centerX = vf.minX + p * vf.width
        return clamp(centerX - width / 2, vf.minX, vf.maxX - width)
    }

    /// The off-edge frame for an auto-hidden tab: the resting pill slid out past
    /// `edge` until only `reveal` points peek back onto the screen as a hover hint
    /// (Dock-style). Only the perpendicular (flush-to-edge) axis moves; the
    /// along-edge position is unchanged. See PLAN.md §13.
    static func hiddenTabFrame(edge: Edge, restingTabFrame f: CGRect, in vf: CGRect, reveal: CGFloat = 3) -> CGRect {
        var frame = f
        switch edge {
        case .left:   frame.origin.x = vf.minX - (f.width - reveal)
        case .right:  frame.origin.x = vf.maxX - reveal
        case .top:    frame.origin.y = vf.maxY - reveal
        case .bottom: frame.origin.y = vf.minY - (f.height - reveal)
        }
        return frame
    }

    /// A thin sliver flush at `edge`, shrunk to `reveal` points on the
    /// perpendicular axis and kept entirely on the tab's own screen (the along-edge
    /// axis is unchanged). Used to auto-hide a tab on an edge it *shares* with
    /// another display, where sliding off would spill onto the neighbor — this
    /// reclaims the space without leaving its screen, instead of fading. Pure, so
    /// it's unit-tested. See PLAN.md §13.
    static func sliverTabFrame(edge: Edge, restingTabFrame f: CGRect, reveal: CGFloat = 3) -> CGRect {
        var frame = f
        switch edge {
        case .left:   frame.size.width = reveal
        case .right:  frame.origin.x = f.maxX - reveal; frame.size.width = reveal
        case .top:    frame.origin.y = f.maxY - reveal; frame.size.height = reveal
        case .bottom: frame.size.height = reveal
        }
        return frame
    }

    /// Whether auto-hiding by sliding the resting tab off `edge` would leave it
    /// visible on *another* display — true when a screen butts against that edge
    /// over the tab's span. On such a shared edge the pill can't actually go
    /// off-screen (it would land on the neighbor), so the caller shrinks it to a
    /// `sliverTabFrame` instead. Pure, so it's unit-tested. See PLAN.md §13.
    static func hiddenFrameSpillsOntoOtherScreens(edge: Edge, restingTabFrame: CGRect,
                                                  screenVisibleFrame: CGRect,
                                                  otherScreenFrames: [CGRect], reveal: CGFloat = 3) -> Bool {
        let hidden = hiddenTabFrame(edge: edge, restingTabFrame: restingTabFrame, in: screenVisibleFrame, reveal: reveal)
        return otherScreenFrames.contains { $0.intersects(hidden) }
    }

    // MARK: Drawer placement

    /// Frame for an opening drawer: it sits **flush against the screen edge**
    /// (like a physical drawer sliding out), sized `contentSize` (capped to the
    /// screen) and centered along the edge on the tab. The tab then rides on the
    /// drawer's inner face — see `openedTabFrame`. This is the "drawer pushes the
    /// tab inward" behavior.
    static func openDrawerFrame(edge: Edge, tabFrame: CGRect, contentSize: CGSize, in visibleFrame: CGRect) -> CGRect {
        let w = min(contentSize.width, visibleFrame.width)
        let h = min(contentSize.height, visibleFrame.height)
        switch edge {
        case .left:
            return CGRect(x: visibleFrame.minX,
                          y: alignVertical(center: tabFrame.midY, height: h, in: visibleFrame),
                          width: w, height: h)
        case .right:
            return CGRect(x: visibleFrame.maxX - w,
                          y: alignVertical(center: tabFrame.midY, height: h, in: visibleFrame),
                          width: w, height: h)
        case .top:
            return CGRect(x: alignHorizontal(center: tabFrame.midX, width: w, in: visibleFrame),
                          y: visibleFrame.maxY - h,
                          width: w, height: h)
        case .bottom:
            return CGRect(x: alignHorizontal(center: tabFrame.midX, width: w, in: visibleFrame),
                          y: visibleFrame.minY,
                          width: w, height: h)
        }
    }

    /// Which inner corners of an open drawer must be squared so its tab joins the
    /// drawer flush. The tab rides the drawer's inward face; if it sits within
    /// `radius` of a corner (e.g. the drawer was clamped toward a screen edge, so
    /// the tab is no longer centered on it), that corner has to be square or a
    /// rounded notch shows at the seam. `start`/`end` run along the inward face:
    /// top→bottom for left/right edges, leading→trailing for top/bottom. Pure, so
    /// it's unit-tested. See PLAN.md §5.
    static func drawerInnerCornersToSquare(edge: Edge, tabFrame: CGRect, drawerFrame: CGRect,
                                           radius: CGFloat) -> (start: Bool, end: Bool) {
        let tolerance: CGFloat = 0.5   // ignore float noise when a centered tab just touches the curve
        if edge.isVertical {
            return (start: tabFrame.maxY > drawerFrame.maxY - radius + tolerance,   // near the top corner
                    end:   tabFrame.minY < drawerFrame.minY + radius - tolerance)   // near the bottom corner
        } else {
            return (start: tabFrame.minX < drawerFrame.minX + radius - tolerance,   // near the leading corner
                    end:   tabFrame.maxX > drawerFrame.maxX - radius + tolerance)   // near the trailing corner
        }
    }

    /// The tab's frame while its drawer is open: pushed in from the edge to ride
    /// flush on the drawer's inner face, keeping its size and along-edge center.
    static func openedTabFrame(edge: Edge, restingTabFrame: CGRect, drawerFrame: CGRect) -> CGRect {
        var frame = restingTabFrame
        switch edge {
        case .left:   frame.origin.x = drawerFrame.maxX
        case .right:  frame.origin.x = drawerFrame.minX - restingTabFrame.width
        case .top:    frame.origin.y = drawerFrame.minY - restingTabFrame.height
        case .bottom: frame.origin.y = drawerFrame.maxY
        }
        return frame
    }

    /// A small **inward** nudge of `openFrame` (toward the screen center), used as
    /// the start/end of the drawer's fade-slide. Nudging inward (rather than
    /// tucking off the edge) keeps the animation on the drawer's own screen, so it
    /// never bleeds onto an adjacent display at a shared edge.
    static func nudgedDrawerFrame(edge: Edge, openFrame: CGRect, by amount: CGFloat) -> CGRect {
        switch edge {
        case .left:   return openFrame.offsetBy(dx: amount, dy: 0)
        case .right:  return openFrame.offsetBy(dx: -amount, dy: 0)
        case .top:    return openFrame.offsetBy(dx: 0, dy: -amount)
        case .bottom: return openFrame.offsetBy(dx: 0, dy: amount)
        }
    }

    // MARK: De-overlap (tabs sharing an edge)

    /// Packs `frames` — already in the desired visual order along `edge` — so none
    /// overlap. Each frame keeps its along-edge position unless it would overlap the
    /// previous one, in which case it's pushed just past it (plus `gap`). If the
    /// packed run overflows the far end of `visibleFrame`, the whole run is shifted
    /// back so the last frame fits on-screen. The cross-edge axis (flush to the edge)
    /// is left untouched. Pure, so it's unit-tested. See PLAN.md §5.
    static func packAlongEdge(frames: [CGRect], edge: Edge, gap: CGFloat, in vf: CGRect) -> [CGRect] {
        guard frames.count > 1 else { return frames }
        let horizontal = !edge.isVertical

        // `a` is the distance from the edge's start (left for top/bottom, top for
        // left/right), so increasing `a` reads left→right or top→bottom.
        func a(of f: CGRect) -> CGFloat { horizontal ? f.minX - vf.minX : vf.maxY - f.maxY }
        func len(of f: CGRect) -> CGFloat { horizontal ? f.width : f.height }
        let axisMax = horizontal ? vf.width : vf.height

        var positions = [CGFloat](repeating: 0, count: frames.count)
        var cursor = -CGFloat.greatestFiniteMagnitude
        for i in frames.indices {
            let start = Swift.max(a(of: frames[i]), cursor)
            positions[i] = start
            cursor = start + len(of: frames[i]) + gap
        }
        // Shift the whole packed run back on-screen if it ran off the far end.
        let lastEnd = positions[frames.count - 1] + len(of: frames[frames.count - 1])
        if lastEnd > axisMax {
            let shift = lastEnd - axisMax
            for i in positions.indices { positions[i] = Swift.max(0, positions[i] - shift) }
        }

        return frames.indices.map { i in
            var f = frames[i]
            if horizontal { f.origin.x = vf.minX + positions[i] }
            else { f.origin.y = vf.maxY - positions[i] - f.height }
            return f
        }
    }

    private static func alignVertical(center: CGFloat, height: CGFloat, in vf: CGRect) -> CGFloat {
        clamp(center - height / 2, vf.minY, vf.maxY - height)
    }

    private static func alignHorizontal(center: CGFloat, width: CGFloat, in vf: CGRect) -> CGFloat {
        clamp(center - width / 2, vf.minX, vf.maxX - width)
    }

    // MARK: Drag inversion

    /// The fractional position along `edge` for a screen-space point `p` — the
    /// inverse of `tabFrame`'s placement, used during drag-to-reposition.
    static func position(forPoint p: CGPoint, edge: Edge, in visibleFrame: CGRect) -> Double {
        switch edge {
        case .left, .right:
            guard visibleFrame.height > 0 else { return 0.5 }
            return ScreenAnchor.clampPosition(Double((visibleFrame.maxY - p.y) / visibleFrame.height))
        case .top, .bottom:
            guard visibleFrame.width > 0 else { return 0.5 }
            return ScreenAnchor.clampPosition(Double((p.x - visibleFrame.minX) / visibleFrame.width))
        }
    }

    // MARK: Helpers

    /// Clamps `v` to `[lo, hi]`; if the window is larger than the available
    /// range (hi < lo), pins to `lo` so it stays on-screen at the edge.
    private static func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        guard hi > lo else { return lo }
        return Swift.min(Swift.max(v, lo), hi)
    }
}
