import XCTest
@testable import MacDring

final class FolderListerTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macdring-folder-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: dir.appendingPathComponent("banana.txt"))
        try Data("x".utf8).write(to: dir.appendingPathComponent("apple.txt"))
        try Data("x".utf8).write(to: dir.appendingPathComponent(".hidden.txt"))
        try fm.createDirectory(at: dir.appendingPathComponent("ZSub"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func folderTab() -> Tab {
        Tab(title: "F", colorHex: "#0A84FF",
            anchor: ScreenAnchor(displayUUID: "D", edge: .right, position: 0.5),
            kind: .folder, folderURL: dir)
    }

    func testListsContentsFoldersFirstSkippingHidden() {
        let items = FolderLister.contents(of: folderTab())
        XCTAssertEqual(items.count, 3)                 // .hidden.txt skipped
        XCTAssertEqual(items[0].kind, .folder)         // directory sorts first
        XCTAssertEqual(items[0].displayName, "ZSub")
        XCTAssertEqual(items[1].kind, .file)
        XCTAssertEqual(items[2].kind, .file)
        XCTAssertTrue(items[1].displayName.hasPrefix("apple"))   // files alphabetical
        XCTAssertTrue(items[2].displayName.hasPrefix("banana"))
        XCTAssertFalse(items.contains { $0.displayName.hasPrefix(".") })
    }

    func testItemsHaveSequentialSlots() {
        let items = FolderLister.contents(of: folderTab())
        XCTAssertEqual(items.map(\.slot), Array(0..<items.count))
    }

    func testNonFolderTabReturnsEmpty() {
        let tab = Tab(title: "I", colorHex: "#0A84FF",
                      anchor: ScreenAnchor(displayUUID: "D", edge: .right, position: 0.5),
                      kind: .items)
        XCTAssertTrue(FolderLister.contents(of: tab).isEmpty)
    }
}
