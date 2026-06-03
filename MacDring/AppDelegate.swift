import AppKit

/// Boots the app: wires the store, display registry, and tab controller, builds
/// the menu-bar item, and seeds a starter tab on first run.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private let preferences = Preferences.shared
    private let store = TabStore()
    private let registry = DisplayRegistry()
    private lazy var controller = TabController(store: store, preferences: preferences, registry: registry)
    private lazy var settingsWindow = SettingsWindowController(preferences: preferences, store: store, registry: registry)

    private var statusItem: NSStatusItem?
    private var launchAtLoginItem: NSMenuItem?

    // MARK: NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }

        if !store.loadedFromDisk && store.tabs.isEmpty {
            seedStarterTab()
        }
        controller.onOpenSettings = { [weak self] tabID in self?.settingsWindow.show(selectTab: tabID) }
        setUpStatusItem()
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.saveAndTeardown()
    }

    // MARK: Status item

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.statusBarImage()
        item.menu = buildMenu()
        statusItem = item
    }

    /// A template menu-bar glyph that echoes the app's motif: a "screen" outline
    /// with a filled tab on its right edge (an edge tab → drawer).
    private static func statusBarImage() -> NSImage {
        let size = NSSize(width: 18, height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            let body = NSRect(x: 1.5, y: 2.5, width: 10.5, height: 11)
            let bodyPath = NSBezierPath(roundedRect: body, xRadius: 2.5, yRadius: 2.5)
            bodyPath.lineWidth = 1.4
            NSColor.black.setStroke()
            bodyPath.stroke()

            let tab = NSRect(x: body.maxX - 1, y: 5, width: 4.5, height: 6)
            NSColor.black.setFill()
            NSBezierPath(roundedRect: tab, xRadius: 1.8, yRadius: 1.8).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let newTabItem = NSMenuItem(title: "New Tab", action: #selector(newTab), keyEquivalent: "n")
        newTabItem.target = self
        menu.addItem(newTabItem)

        let settingsItem = NSMenuItem(title: "MacDring Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)
        launchAtLoginItem = loginItem

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit MacDring", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        preferences.refreshLaunchAtLoginStatus()
        launchAtLoginItem?.state = preferences.launchAtLogin ? .on : .off
    }

    // MARK: Actions

    @objc private func newTab() {
        guard let uuid = registry.mainScreenUUID() else { return }
        // Stagger new right-edge tabs so they don't land exactly on top of each other.
        let rightCount = store.tabs.filter { $0.anchor.edge == .right && $0.anchor.displayUUID == uuid }.count
        let position = max(0.12, min(0.88, 0.5 - 0.08 * Double(rightCount)))
        let tab = Tab(
            title: "New Tab",
            colorHex: preferences.defaultTabColorHex,
            glyph: .symbol("folder.fill"),
            anchor: ScreenAnchor(displayUUID: uuid, edge: .right, position: position, order: rightCount),
            behavior: preferences.newTabBehavior,
            gridColumns: Int(preferences.gridColumns),
            gridRows: Int(preferences.gridRows)
        )
        store.addTab(tab)
    }

    @objc private func openSettings() {
        settingsWindow.show(selectTab: nil)
    }

    @objc private func toggleLaunchAtLogin() {
        preferences.launchAtLogin.toggle()
        launchAtLoginItem?.state = preferences.launchAtLogin ? .on : .off
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: First-run starter tab

    private func seedStarterTab() {
        guard let uuid = registry.mainScreenUUID() else { return }

        var items: [DrawerItem] = []
        for bundleID in ["com.apple.finder", "com.apple.Safari", "com.apple.systempreferences"] {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                items.append(DrawerItem.fromFileURL(url))
            }
        }
        items.append(DrawerItem.fromFileURL(URL(fileURLWithPath: "/Applications", isDirectory: true)))

        let tab = Tab(
            title: "Apps",
            colorHex: preferences.defaultTabColorHex,
            glyph: .symbol("square.grid.2x2.fill"),
            anchor: ScreenAnchor(displayUUID: uuid, edge: .right, position: 0.5, order: 0),
            items: items,
            behavior: preferences.newTabBehavior,
            gridColumns: Int(preferences.gridColumns),
            gridRows: Int(preferences.gridRows)
        )
        store.addTab(tab)
    }

    // MARK: Helpers

    static var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil ||
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
