import XCTest
@testable import MacDring

final class TabLayoutTests: XCTestCase {

    func testUseGlobalFollowsTheGlobalDefault() {
        XCTAssertEqual(TabLayout.useGlobal.resolved(default: .grid), .grid)
        XCTAssertEqual(TabLayout.useGlobal.resolved(default: .list), .list)
    }

    func testGridAndListPinTheirOwnChoice() {
        XCTAssertEqual(TabLayout.grid.resolved(default: .list), .grid)
        XCTAssertEqual(TabLayout.list.resolved(default: .grid), .list)
    }
}
