import XCTest
@testable import MacDring

final class RecentsStoreTests: XCTestCase {

    private func recent(_ name: String, _ path: String, kind: ItemKind = .file) -> RecentItem {
        RecentItem(url: URL(fileURLWithPath: path), kind: kind, name: name, date: Date())
    }

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "recents-test-\(UUID().uuidString)")!
    }

    // MARK: Pure merging

    func testMergingPrependsAndDedupsByURL() {
        let merged = RecentsStore.merging([recent("A", "/a"), recent("B", "/b")],
                                          with: recent("A2", "/a"), limit: 10)
        XCTAssertEqual(merged.map(\.name), ["A2", "B"])   // /a moved to front (deduped), /b kept
    }

    func testMergingCapsToLimitKeepingNewest() {
        let items = (0..<5).map { recent("old\($0)", "/\($0)") }
        let merged = RecentsStore.merging(items, with: recent("new", "/new"), limit: 3)
        XCTAssertEqual(merged.count, 3)
        XCTAssertEqual(merged.first?.name, "new")
    }

    // MARK: Store (injected defaults)

    func testRecordDedupsAndPersists() {
        let defaults = freshDefaults()
        let store = RecentsStore(defaults: defaults)
        store.record(recent("A", "/a"))
        store.record(recent("B", "/b"))
        store.record(recent("A-again", "/a"))
        XCTAssertEqual(store.items.map(\.name), ["A-again", "B"])

        let reloaded = RecentsStore(defaults: defaults)   // round-trips through UserDefaults
        XCTAssertEqual(reloaded.items.map(\.name), ["A-again", "B"])
    }

    func testClear() {
        let store = RecentsStore(defaults: freshDefaults())
        store.record(recent("A", "/a"))
        store.clear()
        XCTAssertTrue(store.items.isEmpty)
    }
}
