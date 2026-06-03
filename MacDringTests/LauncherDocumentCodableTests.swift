import XCTest
@testable import MacDring

final class LauncherDocumentCodableTests: XCTestCase {

    func testFullRoundTrip() throws {
        let item = DrawerItem(kind: .url, displayName: "Example", url: URL(string: "https://example.com"), slot: 4)
        let tab = Tab(
            title: "Work",
            colorHex: "#FF8800",
            glyph: .monogram("W"),
            anchor: ScreenAnchor(displayUUID: "UUID-1", edge: .left, position: 0.25, order: 2),
            items: [item],
            behavior: TabBehavior(openOnHover: true, autoHide: false, keepOpenAfterLaunch: true),
            hotkey: HotkeySpec(keyCode: 13, carbonModifiers: 256)
        )
        let document = LauncherDocument(tabs: [tab])

        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(LauncherDocument.self, from: data)

        XCTAssertEqual(decoded, document)
        XCTAssertEqual(decoded.tabs.first?.glyph, .monogram("W"))
        XCTAssertEqual(decoded.tabs.first?.hotkey, HotkeySpec(keyCode: 13, carbonModifiers: 256))
        XCTAssertEqual(decoded.tabs.first?.items.first?.slot, 4)
    }

    func testSymbolGlyphRoundTrip() throws {
        let glyph = TabGlyph.symbol("folder.fill")
        let data = try JSONEncoder().encode(glyph)
        XCTAssertEqual(try JSONDecoder().decode(TabGlyph.self, from: data), glyph)
    }

    func testTabDecodesWithDefaultsWhenFieldsMissing() throws {
        // Only `anchor` is required; everything else should default.
        let json = #"""
        {"tabs":[{"anchor":{"displayUUID":"D","edge":"right","position":0.5}}]}
        """#.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(LauncherDocument.self, from: json)
        let tab = try XCTUnwrap(decoded.tabs.first)
        XCTAssertEqual(tab.title, "Tab")
        XCTAssertEqual(tab.glyph, .default)
        XCTAssertTrue(tab.items.isEmpty)
        XCTAssertEqual(tab.behavior, .default)
        XCTAssertNil(tab.hotkey)
        XCTAssertEqual(tab.gridColumns, 4)
        XCTAssertEqual(tab.gridRows, 2)
        XCTAssertFalse(tab.locked)
        XCTAssertEqual(decoded.version, LauncherDocument.currentVersion)
    }

    func testEmptyDocumentDecodes() throws {
        let decoded = try JSONDecoder().decode(LauncherDocument.self, from: "{}".data(using: .utf8)!)
        XCTAssertTrue(decoded.tabs.isEmpty)
        XCTAssertEqual(decoded.version, LauncherDocument.currentVersion)
    }
}
