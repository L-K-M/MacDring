import XCTest
@testable import MacDring

final class FreshListerTests: XCTestCase {

    private func result(_ name: String, _ path: String, daysAgo: Double) -> SpotlightQuery.Result {
        SpotlightQuery.Result(url: URL(fileURLWithPath: path), name: name,
                              date: Date(timeIntervalSinceNow: -daysAgo * 86400))
    }

    func testItemsAreNewestFirstWithSequentialSlots() {
        let items = FreshLister.items(from: [
            result("old", "/old", daysAgo: 9),
            result("new", "/new", daysAgo: 1),
            result("mid", "/mid", daysAgo: 5),
        ])
        XCTAssertEqual(items.map(\.displayName), ["new", "mid", "old"])   // most-recently-added first
        XCTAssertEqual(items.map(\.slot), [0, 1, 2])
    }

    func testItemsResolveToTheirURL() throws {
        let url = URL(fileURLWithPath: "/Users/me/Downloads/report.pdf")
        let item = try XCTUnwrap(FreshLister.items(from: [result("report.pdf", url.path, daysAgo: 0)]).first)
        XCTAssertEqual(BookmarkResolver.url(for: item), url)
    }

    func testCapsToLimit() {
        let many = (0..<(FreshLister.limit + 10)).map { result("f\($0)", "/f\($0)", daysAgo: Double($0)) }
        XCTAssertEqual(FreshLister.items(from: many).count, FreshLister.limit)
    }

    func testEmptyResultsProduceNoItems() {
        XCTAssertTrue(FreshLister.items(from: []).isEmpty)
    }

    func testScopesAreTheLandingZones() {
        let home = URL(fileURLWithPath: "/Users/me")
        let names = FreshLister.scopes(home: home).map(\.lastPathComponent)
        XCTAssertEqual(names, ["Downloads", "Desktop", "Documents"])
    }
}
