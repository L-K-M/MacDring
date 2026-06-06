import XCTest
@testable import MacDring

final class DrawerMetricsTests: XCTestCase {

    private let visible = CGRect(x: 0, y: 0, width: 1600, height: 1000)

    func testGridWidthScalesWithColumns() {
        let two = DrawerMetrics.contentSize(itemCount: 8, maxSlot: 7, configuredRows: 2, layout: .grid, iconSize: 64, columns: 2, in: visible)
        let four = DrawerMetrics.contentSize(itemCount: 8, maxSlot: 7, configuredRows: 2, layout: .grid, iconSize: 64, columns: 4, in: visible)
        XCTAssertGreaterThan(four.width, two.width)
    }

    func testConfiguredRowsDriveHeight() {
        let short = DrawerMetrics.contentSize(itemCount: 1, maxSlot: 0, configuredRows: 2, layout: .grid, iconSize: 64, columns: 4, in: visible)
        let tall = DrawerMetrics.contentSize(itemCount: 1, maxSlot: 0, configuredRows: 6, layout: .grid, iconSize: 64, columns: 4, in: visible)
        XCTAssertGreaterThan(tall.height, short.height)
    }

    func testGridGrowsBeyondConfiguredRowsForItemsAndGaps() {
        // configured 2 rows, but an item parked at slot 20 → must grow.
        XCTAssertEqual(DrawerMetrics.gridRowCount(configuredRows: 2, maxSlot: 20, itemCount: 2, columns: 4), 6)
        // configured 3 rows wins when items/slots are smaller.
        XCTAssertEqual(DrawerMetrics.gridRowCount(configuredRows: 3, maxSlot: 3, itemCount: 4, columns: 4), 3)
        // never less than 1.
        XCTAssertEqual(DrawerMetrics.gridRowCount(configuredRows: 1, maxSlot: -1, itemCount: 0, columns: 4), 1)
    }

    func testSizeIsClampedToScreen() {
        let small = CGRect(x: 0, y: 0, width: 400, height: 300)
        let size = DrawerMetrics.contentSize(itemCount: 200, maxSlot: 199, configuredRows: 50, layout: .grid, iconSize: 128, columns: 8, in: small)
        XCTAssertLessThanOrEqual(size.width, small.width - 16)
        XCTAssertLessThanOrEqual(size.height, small.height - 16)
    }

    func testEmptyDrawerHasPositiveSize() {
        let size = DrawerMetrics.contentSize(itemCount: 0, maxSlot: -1, configuredRows: 2, layout: .grid, iconSize: 64, columns: 4, in: visible)
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
    }

    func testListWidthIsIndependentOfItemCount() {
        let a = DrawerMetrics.contentSize(itemCount: 3, maxSlot: 2, configuredRows: 2, layout: .list, iconSize: 48, columns: 4, in: visible)
        let b = DrawerMetrics.contentSize(itemCount: 30, maxSlot: 29, configuredRows: 2, layout: .list, iconSize: 48, columns: 4, in: visible)
        XCTAssertEqual(a.width, b.width)         // width tracks icon size, not count
        XCTAssertGreaterThan(b.height, a.height) // height grows with count
    }

    func testListWidthGrowsWithIconSize() {
        let small = DrawerMetrics.contentSize(itemCount: 4, maxSlot: 3, configuredRows: 2, layout: .list, iconSize: 32, columns: 4, in: visible)
        let large = DrawerMetrics.contentSize(itemCount: 4, maxSlot: 3, configuredRows: 2, layout: .list, iconSize: 128, columns: 4, in: visible)
        XCTAssertGreaterThan(large.width, small.width)
    }

    func testSearchableDrawerReservesRoomForFilterField() {
        // A searchable drawer is taller by exactly the filter field's reserved height,
        // so the grid still fits without a scroll bar (the filter doesn't change width).
        let plain = DrawerMetrics.contentSize(itemCount: 8, maxSlot: 7, configuredRows: 2, layout: .grid, iconSize: 64, columns: 4, searchable: false, in: visible)
        let filtered = DrawerMetrics.contentSize(itemCount: 8, maxSlot: 7, configuredRows: 2, layout: .grid, iconSize: 64, columns: 4, searchable: true, in: visible)
        XCTAssertEqual(filtered.height, plain.height + DrawerMetrics.searchBarHeight, accuracy: 0.5)
        XCTAssertEqual(filtered.width, plain.width)
    }
}
