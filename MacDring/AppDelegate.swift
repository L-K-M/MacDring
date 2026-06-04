import AppKit

/// Boots the app: wires the store, display registry, and tab controller, builds
/// the menu-bar item, and seeds a starter tab on first run.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private let preferences = Preferences.shared
    private let store = TabStore()
    private let registry = DisplayRegistry()
    private lazy var controller = TabController(store: store, preferences: preferences, registry: registry)
    private lazy var settingsWindow = SettingsWindowController(preferences: preferences, store: store, registry: registry)
    private lazy var newTabWindow = NewTabWindowController(preferences: preferences, store: store, registry: registry)

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

    /// A template menu-bar glyph that echoes the app icon: a rounded "screen"
    /// outline with a single drawer pulled up from its bottom edge.
    private static func statusBarImage() -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            // The screen.
            let body = NSRect(x: 2, y: 2, width: 12, height: 12)
            let bodyPath = NSBezierPath(roundedRect: body, xRadius: 3, yRadius: 3)
            bodyPath.lineWidth = 1.4
            NSColor.black.setStroke()
            bodyPath.stroke()

            // A drawer riding the bottom edge, filled so it reads at small sizes.
            let drawer = NSRect(x: 4.75, y: 3, width: 6.5, height: 4)
            NSColor.black.setFill()
            NSBezierPath(roundedRect: drawer, xRadius: 1.6, yRadius: 1.6).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let newItems = NSMenuItem(title: "New Items Tab…", action: #selector(newItemsTab), keyEquivalent: "n")
        newItems.target = self
        menu.addItem(newItems)

        let newNotes = NSMenuItem(title: "New Notes Tab…", action: #selector(newNotesTab), keyEquivalent: "")
        newNotes.target = self
        menu.addItem(newNotes)

        let newFolder = NSMenuItem(title: "New Folder Tab…", action: #selector(newFolderTab), keyEquivalent: "")
        newFolder.target = self
        menu.addItem(newFolder)

        let newDisks = NSMenuItem(title: "New Disks Tab…", action: #selector(newDisksTab), keyEquivalent: "")
        newDisks.target = self
        menu.addItem(newDisks)

        let newNetwork = NSMenuItem(title: "New Network Tab…", action: #selector(newNetworkTab), keyEquivalent: "")
        newNetwork.target = self
        menu.addItem(newNetwork)

        let newCloud = NSMenuItem(title: "New Cloud Tab…", action: #selector(newCloudTab), keyEquivalent: "")
        newCloud.target = self
        menu.addItem(newCloud)

        let newRecents = NSMenuItem(title: "New Recents Tab…", action: #selector(newRecentsTab), keyEquivalent: "")
        newRecents.target = self
        menu.addItem(newRecents)

        menu.addItem(.separator())

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

    @objc private func newItemsTab() { newTabWindow.show(kind: .items) }
    @objc private func newNotesTab() { newTabWindow.show(kind: .notes) }
    @objc private func newFolderTab() { newTabWindow.show(kind: .folder) }
    @objc private func newDisksTab() { newTabWindow.show(kind: .disks) }
    @objc private func newNetworkTab() { newTabWindow.show(kind: .network) }
    @objc private func newCloudTab() { newTabWindow.show(kind: .cloud) }
    @objc private func newRecentsTab() { newTabWindow.show(kind: .recents) }

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
