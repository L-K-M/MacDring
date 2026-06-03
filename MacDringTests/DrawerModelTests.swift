import XCTest
@testable import MacDring

final class DrawerModelTests: XCTestCase {

    func testItemAtSlotFindsByGridSlotIncludingGaps() {
        let model = DrawerModel()
        let a = DrawerItem(kind: .file, displayName: "A", slot: 0)
        let b = DrawerItem(kind: .file, displayName: "B", slot: 3)   // gap at 1, 2
        model.items = [a, b]

        XCTAssertEqual(model.item(atSlot: 0)?.id, a.id)
        XCTAssertEqual(model.item(atSlot: 3)?.id, b.id)
        XCTAssertNil(model.item(atSlot: 1))
        XCTAssertNil(model.item(atSlot: 2))
    }
}
