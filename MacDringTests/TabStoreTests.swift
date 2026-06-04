import XCTest
@testable import MacDring

final class TabStoreTests: XCTestCase {

    private var storeURL: URL!

    override func setUp() {
        super.setUp()
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macdring-store-\(UUID().uuidString)")
            .appendingPathComponent("launcher.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent())
        storeURL = nil
        super.tearDown()
    }

    private func makeTab(_ title: String = "T") -> Tab {
        Tab(title: title,
            colorHex: "#0A84FF",
            anchor: ScreenAnchor(displayUUID: "D1", edge: .right, position: 0.5))
    }

    func testFreshStoreIsEmpty() {
        let store = TabStore(storeURL: storeURL)
        XCTAssertFalse(store.loadedFromDisk)
        XCTAssertTrue(store.tabs.isEmpty)
    }

    func testAddSaveAndReload() {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab("Work")
        store.addTab(tab)
        store.saveNow()

        let reloaded = TabStore(storeURL: storeURL)
        XCTAssertTrue(reloaded.loadedFromDisk)
        XCTAssertEqual(reloaded.tabs.count, 1)
        XCTAssertEqual(reloaded.tabs.first?.title, "Work")
        XCTAssertEqual(reloaded.tabs.first?.id, tab.id)
    }

    func testUpdateAllBehaviorsAppliesToEveryTab() {
        let store = TabStore(storeURL: storeURL)
        var a = makeTab("A"); a.behavior = TabBehavior(openOnHover: false, autoHide: true)
        var b = makeTab("B"); b.behavior = TabBehavior(openOnHover: true, autoHide: true)
        store.addTab(a)
        store.addTab(b)

        store.updateAllBehaviors { $0.autoHide = false }

        XCTAssertTrue(store.tabs.allSatisfy { !$0.behavior.autoHide })
        // Only the targeted field changes; others are untouched.
        XCTAssertFalse(store.tab(id: a.id)?.behavior.openOnHover ?? true)
        XCTAssertTrue(store.tab(id: b.id)?.behavior.openOnHover ?? false)
    }

    func testItemMutations() {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab()
        store.addTab(tab)

        let item = DrawerItem(kind: .url, displayName: "Site", url: URL(string: "https://example.com"))
        store.addItem(item, toTab: tab.id)
        XCTAssertEqual(store.tab(id: tab.id)?.items.count, 1)

        store.removeItem(id: item.id, fromTab: tab.id)
        XCTAssertEqual(store.tab(id: tab.id)?.items.count, 0)
    }

    func testSetAnchor() {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab()
        store.addTab(tab)

        let newAnchor = ScreenAnchor(displayUUID: "D2", edge: .bottom, position: 0.2, order: 1)
        store.setAnchor(newAnchor, forTab: tab.id)
        XCTAssertEqual(store.tab(id: tab.id)?.anchor, newAnchor)
    }

    func testAddItemAssignsSequentialSlots() {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab()
        store.addTab(tab)
        store.addItem(DrawerItem(kind: .file, displayName: "A"), toTab: tab.id)
        store.addItem(DrawerItem(kind: .file, displayName: "B"), toTab: tab.id)
        XCTAssertEqual(store.tab(id: tab.id)?.items.map(\.slot).sorted(), [0, 1])
    }

    func testAddItemSkipsDuplicateTarget() {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab()
        store.addTab(tab)
        let url = URL(fileURLWithPath: "/Applications/Safari.app")
        store.addItem(DrawerItem(kind: .application, displayName: "Safari", url: url), toTab: tab.id)
        // Same target, different display name / id — should not be added again.
        store.addItem(DrawerItem(kind: .application, displayName: "Safari again", url: url), toTab: tab.id)
        XCTAssertEqual(store.tab(id: tab.id)?.items.count, 1)
    }

    func testAddItemAllowsDistinctTargets() {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab()
        store.addTab(tab)
        store.addItem(DrawerItem(kind: .url, displayName: "A", url: URL(string: "https://a.example")), toTab: tab.id)
        store.addItem(DrawerItem(kind: .url, displayName: "B", url: URL(string: "https://b.example")), toTab: tab.id)
        XCTAssertEqual(store.tab(id: tab.id)?.items.count, 2)
    }

    func testPlaceItemMovesToEmptySlotLeavingGap() {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab()
        store.addTab(tab)
        let a = DrawerItem(kind: .file, displayName: "A")
        store.addItem(a, toTab: tab.id)        // slot 0

        store.placeItem(a.id, atSlot: 5, inTab: tab.id)
        XCTAssertEqual(store.tab(id: tab.id)?.items.first { $0.id == a.id }?.slot, 5)
        XCTAssertNil(store.tab(id: tab.id)?.items.first { $0.slot == 0 })   // gap left behind
    }

    func testPlaceItemSwapsWhenSlotOccupied() {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab()
        store.addTab(tab)
        let a = DrawerItem(kind: .file, displayName: "A")
        let b = DrawerItem(kind: .file, displayName: "B")
        store.addItem(a, toTab: tab.id)        // slot 0
        store.addItem(b, toTab: tab.id)        // slot 1

        store.placeItem(a.id, atSlot: 1, inTab: tab.id)
        let items = store.tab(id: tab.id)!.items
        XCTAssertEqual(items.first { $0.id == a.id }?.slot, 1)
        XCTAssertEqual(items.first { $0.id == b.id }?.slot, 0)
    }

    func testAssigningMissingSlotsFillsGapsAndKeepsValidSlots() {
        let items = [
            DrawerItem(kind: .file, displayName: "A", slot: -1),
            DrawerItem(kind: .file, displayName: "B", slot: 2),    // keep; leaves a gap at 1
            DrawerItem(kind: .file, displayName: "C", slot: -1),
        ].assigningMissingSlots()
        let bySlot = Dictionary(uniqueKeysWithValues: items.map { ($0.displayName, $0.slot) })
        XCTAssertEqual(bySlot["B"], 2)
        XCTAssertEqual(Set([bySlot["A"], bySlot["C"]]), Set([0, 1]))
    }

    func testAssigningMissingSlotsResolvesDuplicates() {
        let items = [
            DrawerItem(kind: .file, displayName: "A", slot: 0),
            DrawerItem(kind: .file, displayName: "B", slot: 0),
        ].assigningMissingSlots()
        XCTAssertEqual(Set(items.map(\.slot)), Set([0, 1]))
    }

    func testRemoveTab() {
        let store = TabStore(storeURL: storeURL)
        let tab = makeTab()
        store.addTab(tab)
        store.removeTab(id: tab.id)
        XCTAssertTrue(store.tabs.isEmpty)
    }

    func testOnChangeFires() {
        let store = TabStore(storeURL: storeURL)
        var changes = 0
        store.onChange = { changes += 1 }
        store.addTab(makeTab())
        store.addItem(DrawerItem(kind: .file, displayName: "x"), toTab: store.tabs[0].id)
        XCTAssertEqual(changes, 2)
    }

    func testRecoversFromBackupWhenPrimaryCorrupt() throws {
        // Write a good document, then corrupt the primary file; the .bak should load.
        let store = TabStore(storeURL: storeURL)
        store.addTab(makeTab("Backed"))
        store.saveNow()                                   // creates launcher.json
        store.addTab(makeTab("Second"))
        store.saveNow()                                   // copies prior -> .bak, writes new

        try "{ not valid json".data(using: .utf8)!.write(to: storeURL)
        let reloaded = TabStore(storeURL: storeURL)
        XCTAssertTrue(reloaded.loadedFromDisk)            // recovered from .bak
        XCTAssertFalse(reloaded.tabs.isEmpty)
    }
}
