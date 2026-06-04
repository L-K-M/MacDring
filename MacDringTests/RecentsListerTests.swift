import XCTest
@testable import MacDring

final class RecentsListerTests: XCTestCase {

    private func store() -> RecentsStore {
        RecentsStore(defaults: UserDefaults(suiteName: "recents-lister-\(UUID().uuidString)")!)
    }

    private func recentsTab() -> Tab {
        Tab(title: "R", colorHex: "#0A84FF",
            anchor: ScreenAnchor(displayUUID: "D", edge: .right, position: 0.5), kind: .recents)
    }

    func testContentsMapsRecentsMostRecentFirst() {
        let s = store()
        s.record(RecentItem(url: URL(fileURLWithPath: "/Applications/Safari.app"),
                            kind: .application, name: "Safari", date: Date()))
        s.record(RecentItem(url: URL(string: "https://example.com")!,
                            kind: .url, name: "example", date: Date()))
        let items = RecentsLister.contents(of: recentsTab(), store: s)
        XCTAssertEqual(items.map(\.displayName), ["example", "Safari"])   // most recent first
        XCTAssertEqual(items.map(\.kind), [.url, .application])
        XCTAssertEqual(items.map(\.slot), [0, 1])
    }

    func testItemsResolveToTheirURL() throws {
        let s = store()
        let url = URL(fileURLWithPath: "/Users/me/Documents/report.pdf")
        s.record(RecentItem(url: url, kind: .file, name: "report.pdf", date: Date()))
        let item = try XCTUnwrap(RecentsLister.contents(of: recentsTab(), store: s).first)
        XCTAssertEqual(BookmarkResolver.url(for: item), url)
    }

    func testNonRecentsTabReturnsEmpty() {
        let tab = Tab(title: "I", colorHex: "#0A84FF",
                      anchor: ScreenAnchor(displayUUID: "D", edge: .right, position: 0.5), kind: .items)
        XCTAssertTrue(RecentsLister.contents(of: tab, store: store()).isEmpty)
    }
}
