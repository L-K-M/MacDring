import XCTest
@testable import MacDring

final class EdgeLayoutTests: XCTestCase {

    private let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let pill = CGSize(width: 40, height: 120)

    // MARK: Tab placement

    func testRightEdgeCenteredTab() {
        let frame = EdgeLayout.tabFrame(edge: .right, position: 0.5, size: pill, in: visible)
        XCTAssertEqual(frame.maxX, visible.maxX, accuracy: 0.001)          // flush to right
        XCTAssertEqual(frame.midY, 400, accuracy: 0.001)                   // vertically centered
        XCTAssertEqual(frame.width, 40, accuracy: 0.001)
    }

    func testLeftEdgeIsFlushLeft() {
        let frame = EdgeLayout.tabFrame(edge: .left, position: 0.5, size: pill, in: visible)
        XCTAssertEqual(frame.minX, visible.minX, accuracy: 0.001)
    }

    func testBottomEdgeIsFlushBottom() {
        let frame = EdgeLayout.tabFrame(edge: .bottom, position: 0.5, size: pill, in: visible)
        XCTAssertEqual(frame.minY, visible.minY, accuracy: 0.001)
        XCTAssertEqual(frame.midX, 500, accuracy: 0.001)
    }

    func testTopEdgeIsFlushTop() {
        let frame = EdgeLayout.tabFrame(edge: .top, position: 0.5, size: pill, in: visible)
        XCTAssertEqual(frame.maxY, visible.maxY, accuracy: 0.001)
    }

    func testVerticalPositionZeroIsTopAndClampedOnScreen() {
        // position 0 = top; the pill is pinned fully on-screen at the top.
        let frame = EdgeLayout.tabFrame(edge: .right, position: 0, size: pill, in: visible)
        XCTAssertEqual(frame.maxY, visible.maxY, accuracy: 0.001)
        XCTAssertLessThanOrEqual(frame.maxY, visible.maxY + 0.001)
    }

    func testVerticalPositionOneIsBottomAndClampedOnScreen() {
        let frame = EdgeLayout.tabFrame(edge: .right, position: 1, size: pill, in: visible)
        XCTAssertEqual(frame.minY, visible.minY, accuracy: 0.001)
    }

    func testPositionIsClampedIntoRange() {
        let high = EdgeLayout.tabFrame(edge: .right, position: 5, size: pill, in: visible)
        let one = EdgeLayout.tabFrame(edge: .right, position: 1, size: pill, in: visible)
        XCTAssertEqual(high, one)
    }

    // MARK: Auto-hide (off-edge) frame

    func testHiddenTabLeavesOnlyASliverOnScreen() {
        let reveal: CGFloat = 3
        for edge in Edge.allCases {
            let resting = EdgeLayout.tabFrame(edge: edge, position: 0.5, size: pill, in: visible)
            let hidden = EdgeLayout.hiddenTabFrame(edge: edge, restingTabFrame: resting, in: visible, reveal: reveal)

            // Size is unchanged — the pill just slides out past the edge.
            XCTAssertEqual(hidden.size.width, resting.size.width, accuracy: 0.001)
            XCTAssertEqual(hidden.size.height, resting.size.height, accuracy: 0.001)

            // Exactly `reveal` points remain inside the screen on the tab's edge.
            switch edge {
            case .left:   XCTAssertEqual(hidden.maxX, visible.minX + reveal, accuracy: 0.001)
            case .right:  XCTAssertEqual(hidden.minX, visible.maxX - reveal, accuracy: 0.001)
            case .top:    XCTAssertEqual(hidden.minY, visible.maxY - reveal, accuracy: 0.001)
            case .bottom: XCTAssertEqual(hidden.maxY, visible.minY + reveal, accuracy: 0.001)
            }
        }
    }

    func testHiddenTabKeepsAlongEdgePosition() {
        // The flush-to-edge axis moves; the along-edge axis stays put.
        let vertical = EdgeLayout.tabFrame(edge: .right, position: 0.3, size: pill, in: visible)
        XCTAssertEqual(EdgeLayout.hiddenTabFrame(edge: .right, restingTabFrame: vertical, in: visible).minY,
                       vertical.minY, accuracy: 0.001)

        let horizontal = EdgeLayout.tabFrame(edge: .bottom, position: 0.7, size: CGSize(width: 120, height: 40), in: visible)
        XCTAssertEqual(EdgeLayout.hiddenTabFrame(edge: .bottom, restingTabFrame: horizontal, in: visible).minX,
                       horizontal.minX, accuracy: 0.001)
    }

    func testAutoHideSpillIsDetectedOnAnEdgeSharedWithAnotherDisplay() {
        // A right display whose left edge butts against a left display: hiding a
        // left-edge tab there would slide onto the neighbor.
        let rightVisible = CGRect(x: 1000, y: 0, width: 1000, height: 760)
        let leftFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let resting = EdgeLayout.tabFrame(edge: .left, position: 0.5, size: pill, in: rightVisible)

        XCTAssertTrue(EdgeLayout.hiddenFrameSpillsOntoOtherScreens(
            edge: .left, restingTabFrame: resting, screenVisibleFrame: rightVisible, otherScreenFrames: [leftFrame]))
    }

    func testAutoHideDoesNotSpillOnAnOuterEdge() {
        // The right display's *right* edge is the outer edge of the desktop.
        let rightVisible = CGRect(x: 1000, y: 0, width: 1000, height: 760)
        let leftFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let resting = EdgeLayout.tabFrame(edge: .right, position: 0.5, size: pill, in: rightVisible)

        XCTAssertFalse(EdgeLayout.hiddenFrameSpillsOntoOtherScreens(
            edge: .right, restingTabFrame: resting, screenVisibleFrame: rightVisible, otherScreenFrames: [leftFrame]))
    }

    func testAutoHideDoesNotSpillWhenNeighborMissesTheTabSpan() {
        // A neighbor stacked far above doesn't overlap a mid-height left-edge tab,
        // so sliding off the (locally outer) left edge truly leaves the screen.
        let rightVisible = CGRect(x: 1000, y: 0, width: 1000, height: 760)
        let neighborAbove = CGRect(x: 0, y: 2000, width: 1000, height: 800)
        let resting = EdgeLayout.tabFrame(edge: .left, position: 0.5, size: pill, in: rightVisible)

        XCTAssertFalse(EdgeLayout.hiddenFrameSpillsOntoOtherScreens(
            edge: .left, restingTabFrame: resting, screenVisibleFrame: rightVisible, otherScreenFrames: [neighborAbove]))
    }

    func testSliverTabFrameStaysOnScreenFlushToEdge() {
        let reveal: CGFloat = 3
        for edge in Edge.allCases {
            let resting = EdgeLayout.tabFrame(edge: edge, position: 0.5, size: pill, in: visible)
            let sliver = EdgeLayout.sliverTabFrame(edge: edge, restingTabFrame: resting, reveal: reveal)

            // Entirely within its own screen — never spills onto a neighbor.
            XCTAssertTrue(visible.insetBy(dx: -0.01, dy: -0.01).contains(sliver), "sliver left the screen on \(edge): \(sliver)")
            switch edge {
            case .left:
                XCTAssertEqual(sliver.minX, visible.minX, accuracy: 0.001)   // flush, on-screen
                XCTAssertEqual(sliver.width, reveal, accuracy: 0.001)
                XCTAssertEqual(sliver.minY, resting.minY, accuracy: 0.001)   // along-edge unchanged
            case .right:
                XCTAssertEqual(sliver.maxX, visible.maxX, accuracy: 0.001)
                XCTAssertEqual(sliver.width, reveal, accuracy: 0.001)
            case .top:
                XCTAssertEqual(sliver.maxY, visible.maxY, accuracy: 0.001)
                XCTAssertEqual(sliver.height, reveal, accuracy: 0.001)
            case .bottom:
                XCTAssertEqual(sliver.minY, visible.minY, accuracy: 0.001)
                XCTAssertEqual(sliver.height, reveal, accuracy: 0.001)
            }
        }
    }

    // MARK: Drawer placement (flush to edge) + opened tab

    func testOpenDrawerIsFlushToItsEdge() {
        let tabR = EdgeLayout.tabFrame(edge: .right, position: 0.5, size: pill, in: visible)
        let dR = EdgeLayout.openDrawerFrame(edge: .right, tabFrame: tabR, contentSize: CGSize(width: 300, height: 400), in: visible)
        XCTAssertEqual(dR.maxX, visible.maxX, accuracy: 0.001)

        let tabB = EdgeLayout.tabFrame(edge: .bottom, position: 0.5, size: pill, in: visible)
        let dB = EdgeLayout.openDrawerFrame(edge: .bottom, tabFrame: tabB, contentSize: CGSize(width: 300, height: 400), in: visible)
        XCTAssertEqual(dB.minY, visible.minY, accuracy: 0.001)
    }

    func testOpenDrawerIsCenteredOnTabAlongEdge() {
        let tab = EdgeLayout.tabFrame(edge: .bottom, position: 0.3, size: pill, in: visible)
        let drawer = EdgeLayout.openDrawerFrame(edge: .bottom, tabFrame: tab, contentSize: CGSize(width: 300, height: 200), in: visible)
        XCTAssertEqual(drawer.midX, tab.midX, accuracy: 0.001)
    }

    func testOpenDrawerIsClampedToScreen() {
        for edge in Edge.allCases {
            let tab = EdgeLayout.tabFrame(edge: edge, position: 0.5, size: pill, in: visible)
            let drawer = EdgeLayout.openDrawerFrame(edge: edge, tabFrame: tab,
                                                    contentSize: CGSize(width: 9000, height: 9000), in: visible)
            XCTAssertTrue(visible.insetBy(dx: -0.5, dy: -0.5).contains(drawer),
                          "drawer left the screen on \(edge): \(drawer)")
        }
    }

    func testOpenedTabRidesOnDrawerInnerFace() {
        // The tab is pushed in from the edge to sit flush on the drawer's inner
        // face — same size, touching, not overlapping the drawer's interior.
        for edge in Edge.allCases {
            let tab = EdgeLayout.tabFrame(edge: edge, position: 0.5, size: pill, in: visible)
            let drawer = EdgeLayout.openDrawerFrame(edge: edge, tabFrame: tab, contentSize: CGSize(width: 300, height: 300), in: visible)
            let opened = EdgeLayout.openedTabFrame(edge: edge, restingTabFrame: tab, drawerFrame: drawer)

            XCTAssertEqual(opened.width, tab.width, accuracy: 0.001)
            XCTAssertEqual(opened.height, tab.height, accuracy: 0.001)
            switch edge {
            case .right:  XCTAssertEqual(opened.maxX, drawer.minX, accuracy: 0.001)
            case .left:   XCTAssertEqual(opened.minX, drawer.maxX, accuracy: 0.001)
            case .top:    XCTAssertEqual(opened.maxY, drawer.minY, accuracy: 0.001)
            case .bottom: XCTAssertEqual(opened.minY, drawer.maxY, accuracy: 0.001)
            }
            XCTAssertFalse(opened.insetBy(dx: 0.5, dy: 0.5).intersects(drawer),
                           "opened tab overlaps drawer interior on \(edge)")
        }
    }

    // MARK: Drawer inner-corner squaring (flush tab join)

    func testCenteredTabKeepsBothDrawerCornersRounded() {
        // Drawer centered on the tab with the straight run ≥ tab length → neither
        // inner corner needs squaring.
        let radius: CGFloat = 14
        let tab = EdgeLayout.tabFrame(edge: .left, position: 0.5, size: pill, in: visible)
        let drawer = EdgeLayout.openDrawerFrame(edge: .left, tabFrame: tab,
                                                contentSize: CGSize(width: 300, height: pill.height + 2 * radius), in: visible)
        let corners = EdgeLayout.drawerInnerCornersToSquare(edge: .left, tabFrame: tab, drawerFrame: drawer, radius: radius)
        XCTAssertFalse(corners.start)
        XCTAssertFalse(corners.end)
    }

    func testTabAtBottomSquaresOnlyTheBottomInnerCorner() {
        // A clamped drawer near the bottom: the tab sits at the bottom corner (the
        // reported bug), so only the bottom (end) inner corner is squared.
        let radius: CGFloat = 14
        let tab = EdgeLayout.tabFrame(edge: .left, position: 1.0, size: pill, in: visible)   // flush to the bottom
        let drawer = EdgeLayout.openDrawerFrame(edge: .left, tabFrame: tab,
                                                contentSize: CGSize(width: 300, height: 400), in: visible)
        let corners = EdgeLayout.drawerInnerCornersToSquare(edge: .left, tabFrame: tab, drawerFrame: drawer, radius: radius)
        XCTAssertFalse(corners.start)
        XCTAssertTrue(corners.end)
    }

    func testTabAtTopSquaresOnlyTheTopInnerCorner() {
        let radius: CGFloat = 14
        let tab = EdgeLayout.tabFrame(edge: .right, position: 0.0, size: pill, in: visible)   // flush to the top
        let drawer = EdgeLayout.openDrawerFrame(edge: .right, tabFrame: tab,
                                                contentSize: CGSize(width: 300, height: 400), in: visible)
        let corners = EdgeLayout.drawerInnerCornersToSquare(edge: .right, tabFrame: tab, drawerFrame: drawer, radius: radius)
        XCTAssertTrue(corners.start)
        XCTAssertFalse(corners.end)
    }

    func testTabAtTrailingEndSquaresOnlyTheTrailingInnerCorner() {
        // Horizontal edge: a tab clamped to the right squares the trailing corner.
        let radius: CGFloat = 14
        let wide = CGSize(width: 120, height: 40)
        let tab = EdgeLayout.tabFrame(edge: .bottom, position: 1.0, size: wide, in: visible)
        let drawer = EdgeLayout.openDrawerFrame(edge: .bottom, tabFrame: tab,
                                                contentSize: CGSize(width: 300, height: 300), in: visible)
        let corners = EdgeLayout.drawerInnerCornersToSquare(edge: .bottom, tabFrame: tab, drawerFrame: drawer, radius: radius)
        XCTAssertFalse(corners.start)
        XCTAssertTrue(corners.end)
    }

    func testNudgedDrawerStaysOnScreenSameSize() {
        for edge in Edge.allCases {
            let tab = EdgeLayout.tabFrame(edge: edge, position: 0.5, size: pill, in: visible)
            let open = EdgeLayout.openDrawerFrame(edge: edge, tabFrame: tab, contentSize: CGSize(width: 300, height: 300), in: visible)
            let nudged = EdgeLayout.nudgedDrawerFrame(edge: edge, openFrame: open, by: 22)
            XCTAssertEqual(nudged.size.width, open.size.width, accuracy: 0.001)
            XCTAssertEqual(nudged.size.height, open.size.height, accuracy: 0.001)   // pure translation
            // Nudge is inward, so it stays within the screen (never crosses the edge).
            XCTAssertTrue(visible.contains(nudged), "nudged drawer left the screen for \(edge)")
        }
    }

    // MARK: Drag inversion

    func testPositionForPointRoundTripsVerticalEdge() {
        let tab = EdgeLayout.tabFrame(edge: .right, position: 0.3, size: pill, in: visible)
        let center = CGPoint(x: tab.midX, y: tab.midY)
        let recovered = EdgeLayout.position(forPoint: center, edge: .right, in: visible)
        XCTAssertEqual(recovered, 0.3, accuracy: 0.02)
    }

    func testPositionForPointRoundTripsHorizontalEdge() {
        let tab = EdgeLayout.tabFrame(edge: .bottom, position: 0.7, size: pill, in: visible)
        let center = CGPoint(x: tab.midX, y: tab.midY)
        let recovered = EdgeLayout.position(forPoint: center, edge: .bottom, in: visible)
        XCTAssertEqual(recovered, 0.7, accuracy: 0.02)
    }

    func testPlacementWorksWithOffsetVisibleFrame() {
        // A secondary display's visibleFrame has a non-zero origin.
        let secondary = CGRect(x: 1440, y: 100, width: 1280, height: 700)
        let frame = EdgeLayout.tabFrame(edge: .left, position: 0.5, size: pill, in: secondary)
        XCTAssertEqual(frame.minX, secondary.minX, accuracy: 0.001)
        XCTAssertEqual(frame.midY, secondary.midY, accuracy: 0.001)
    }

    // MARK: De-overlap

    func testStackedVerticalTabsAreSpacedAlongEdge() {
        // Two right-edge tabs at the same position would overlap exactly.
        let f = EdgeLayout.tabFrame(edge: .right, position: 0.5, size: pill, in: visible)
        let packed = EdgeLayout.packAlongEdge(frames: [f, f], edge: .right, gap: 6, in: visible)

        XCTAssertEqual(packed[0], f)                                   // first stays put
        XCTAssertEqual(packed[1].minX, f.minX, accuracy: 0.001)       // still flush right
        // The second sits just below the first (lower y) with the gap between them.
        XCTAssertEqual(packed[1].maxY, packed[0].minY - 6, accuracy: 0.001)
        XCTAssertFalse(packed[0].intersects(packed[1]))
    }

    func testStackedHorizontalTabsAreSpacedAlongEdge() {
        let wide = CGSize(width: 120, height: 40)
        let f = EdgeLayout.tabFrame(edge: .bottom, position: 0.5, size: wide, in: visible)
        let packed = EdgeLayout.packAlongEdge(frames: [f, f], edge: .bottom, gap: 6, in: visible)

        XCTAssertEqual(packed[0], f)
        XCTAssertEqual(packed[1].minY, f.minY, accuracy: 0.001)       // still flush bottom
        XCTAssertEqual(packed[1].minX, packed[0].maxX + 6, accuracy: 0.001)
        XCTAssertFalse(packed[0].intersects(packed[1]))
    }

    func testNonOverlappingFramesAreLeftAlone() {
        let a = EdgeLayout.tabFrame(edge: .right, position: 0.1, size: pill, in: visible)
        let b = EdgeLayout.tabFrame(edge: .right, position: 0.9, size: pill, in: visible)
        let packed = EdgeLayout.packAlongEdge(frames: [a, b], edge: .right, gap: 6, in: visible)
        XCTAssertEqual(packed[0], a)
        XCTAssertEqual(packed[1], b)
    }

    func testOverflowingRunIsShiftedBackOnScreen() {
        // Three tall pills can't all fit from the top without running off the bottom;
        // the run is shifted up so the last one stays on screen.
        let tall = CGSize(width: 40, height: 300)
        let top = EdgeLayout.tabFrame(edge: .right, position: 0.0, size: tall, in: visible)
        let packed = EdgeLayout.packAlongEdge(frames: [top, top, top], edge: .right, gap: 6, in: visible)
        for frame in packed {
            XCTAssertGreaterThanOrEqual(frame.minY, visible.minY - 0.001)
            XCTAssertLessThanOrEqual(frame.maxY, visible.maxY + 0.001)
        }
    }

    func testSingleFrameIsUnchanged() {
        let f = EdgeLayout.tabFrame(edge: .left, position: 0.3, size: pill, in: visible)
        XCTAssertEqual(EdgeLayout.packAlongEdge(frames: [f], edge: .left, gap: 6, in: visible), [f])
    }
}
