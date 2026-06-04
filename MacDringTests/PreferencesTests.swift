import XCTest
import AppKit
@testable import MacDring

final class PreferencesTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "com.macdring.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsWhenEmpty() {
        let prefs = Preferences(defaults: defaults)
        XCTAssertEqual(prefs.drawerMaterial, Preferences.Default.drawerMaterial)
        XCTAssertEqual(prefs.iconSize, Preferences.Default.iconSize)
        XCTAssertEqual(prefs.drawerLayout, .grid)
        XCTAssertEqual(prefs.tabThickness, Preferences.Default.tabThickness)
        XCTAssertEqual(prefs.disconnectPolicy, .park)
        XCTAssertTrue(prefs.launchOnSingleClick)
        XCTAssertEqual(prefs.newTabConcealment, .never)
    }

    func testNewTabConcealmentRoundTripAndSeedsBehavior() {
        let prefs = Preferences(defaults: defaults)
        prefs.newTabConcealment = .fade
        XCTAssertEqual(prefs.newTabBehavior.concealment, .fade)   // seeds new tabs

        let reloaded = Preferences(defaults: defaults)
        XCTAssertEqual(reloaded.newTabConcealment, .fade)
    }

    func testEnumRoundTrip() {
        let prefs = Preferences(defaults: defaults)
        prefs.drawerMaterial = .sidebar
        prefs.drawerLayout = .list
        prefs.disconnectPolicy = .moveToMain
        prefs.tabWindowLevel = .normal

        let reloaded = Preferences(defaults: defaults)
        XCTAssertEqual(reloaded.drawerMaterial, .sidebar)
        XCTAssertEqual(reloaded.drawerLayout, .list)
        XCTAssertEqual(reloaded.disconnectPolicy, .moveToMain)
        XCTAssertEqual(reloaded.tabWindowLevel, .normal)
    }

    func testNumericRoundTrip() {
        let prefs = Preferences(defaults: defaults)
        prefs.iconSize = 96
        prefs.gridColumns = 6
        prefs.cornerRadius = 20
        prefs.tabThickness = 50
        prefs.fadedOpacity = 0.35

        let reloaded = Preferences(defaults: defaults)
        XCTAssertEqual(reloaded.iconSize, 96)
        XCTAssertEqual(reloaded.gridColumns, 6)
        XCTAssertEqual(reloaded.cornerRadius, 20)
        XCTAssertEqual(reloaded.tabThickness, 50)
        XCTAssertEqual(reloaded.fadedOpacity, 0.35)
    }

    func testFadedOpacityDefaultAndClamp() {
        XCTAssertEqual(Preferences(defaults: defaults).fadedOpacity, Preferences.Default.fadedOpacity)

        defaults.set(5.0, forKey: "fadedOpacity")
        XCTAssertLessThanOrEqual(Preferences(defaults: defaults).fadedOpacity, 0.9)
        defaults.set(0.0, forKey: "fadedOpacity")
        XCTAssertGreaterThanOrEqual(Preferences(defaults: defaults).fadedOpacity, 0.05)
    }

    func testOutOfRangeValuesAreClamped() {
        defaults.set(100_000.0, forKey: "iconSize")
        defaults.set(99.0, forKey: "gridColumns")
        defaults.set(-5.0, forKey: "cornerRadius")
        defaults.set(1_000.0, forKey: "tabThickness")
        defaults.set(-10.0, forKey: "animationMs")

        let prefs = Preferences(defaults: defaults)
        XCTAssertLessThanOrEqual(prefs.iconSize, 128)
        XCTAssertLessThanOrEqual(prefs.gridColumns, 12)
        XCTAssertGreaterThanOrEqual(prefs.cornerRadius, 0)
        XCTAssertLessThanOrEqual(prefs.tabThickness, 64)
        XCTAssertGreaterThanOrEqual(prefs.animationMs, 0)
    }

    func testNonFiniteValueFallsBackToDefault() {
        defaults.set(Double.nan, forKey: "iconSize")
        XCTAssertEqual(Preferences(defaults: defaults).iconSize, Preferences.Default.iconSize)
    }

    func testInvalidStoredColorFallsBackToDefault() {
        defaults.set("not-a-color", forKey: "defaultTabColorHex")
        XCTAssertEqual(Preferences(defaults: defaults).defaultTabColorHex, Preferences.Default.defaultTabColorHex)
    }

    func testColorHexRoundTrip() {
        XCTAssertEqual(NSColor(hex: "#0A84FF")?.hexString, "#0A84FF")
        XCTAssertNil(NSColor(hex: "nothex"))
    }
}
