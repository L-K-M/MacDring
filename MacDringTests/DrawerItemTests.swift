import XCTest
@testable import MacDring

final class DrawerItemTests: XCTestCase {

    func testFromDroppedURLMakesLinkItemForWebURL() {
        let item = DrawerItem.fromDroppedURL(URL(string: "https://example.com/path")!)
        XCTAssertEqual(item.kind, .url)
        XCTAssertEqual(item.url, URL(string: "https://example.com/path"))
        XCTAssertEqual(item.displayName, "example.com")   // host, not the full URL
        XCTAssertNil(item.bookmark)                        // links aren't bookmarked
    }

    func testFromDroppedURLFallsBackToAbsoluteStringWhenNoHost() {
        let item = DrawerItem.fromDroppedURL(URL(string: "mailto:hi@example.com")!)
        XCTAssertEqual(item.kind, .url)
        XCTAssertEqual(item.displayName, "mailto:hi@example.com")
    }

    func testFromDroppedURLMakesFileItemForFileURL() {
        let item = DrawerItem.fromDroppedURL(URL(fileURLWithPath: "/usr/bin", isDirectory: true))
        XCTAssertEqual(item.kind, .folder)                 // a directory on disk
        XCTAssertEqual(item.url?.path, "/usr/bin")
    }

    func testFromLinkDefaultsScheme() {
        let item = DrawerItem.fromLink("example.com")
        XCTAssertEqual(item?.kind, .url)
        XCTAssertEqual(item?.url?.scheme, "https")
    }
}
