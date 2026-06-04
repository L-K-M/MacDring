import XCTest
@testable import MacDring

final class NetworkListerTests: XCTestCase {

    private func volume(_ name: String,
                        isLocal: Bool = false,
                        browsable: Bool = true) -> NetworkLister.Volume {
        NetworkLister.Volume(
            url: URL(fileURLWithPath: "/Volumes/\(name)", isDirectory: true),
            name: name,
            isLocal: isLocal,
            isBrowsable: browsable
        )
    }

    private func cloud(_ name: String, path: String? = nil) -> NetworkLister.CloudRoot {
        NetworkLister.CloudRoot(
            url: URL(fileURLWithPath: path ?? "/Users/me/Library/CloudStorage/\(name)", isDirectory: true),
            name: name
        )
    }

    // MARK: Network share filtering

    func testKeepsRemoteBrowsableVolumesOnly() {
        let share = volume("Server")                       // remote (not local) → kept
        let local = volume("Macintosh HD", isLocal: true)  // a local disk → excluded
        let usb = volume("USB", isLocal: true)             // local removable → excluded (Disks tab's job)
        let hidden = volume("vm", browsable: false)        // hidden system mount → excluded
        let items = NetworkLister.items(networkVolumes: [share, local, usb, hidden], cloudRoots: [])
        XCTAssertEqual(items.map(\.displayName), ["Server"])
        XCTAssertEqual(items.first?.kind, .disk)           // shares are ejectable .disk items
    }

    func testIsNetworkPredicate() {
        XCTAssertTrue(NetworkLister.isNetwork(volume("Share")))                 // remote, browsable
        XCTAssertFalse(NetworkLister.isNetwork(volume("Disk", isLocal: true)))  // local
        XCTAssertFalse(NetworkLister.isNetwork(volume("Hidden", browsable: false)))
    }

    // MARK: Cloud roots

    func testCloudRootsBecomeFolderItems() {
        let items = NetworkLister.items(networkVolumes: [], cloudRoots: [cloud("iCloud Drive"), cloud("Dropbox")])
        XCTAssertTrue(items.allSatisfy { $0.kind == .folder })  // cloud roots are openable folders
        XCTAssertEqual(Set(items.map(\.displayName)), ["iCloud Drive", "Dropbox"])
    }

    // MARK: Ordering, slots, and combination

    func testSharesPrecedeCloudsEachSortedWithSequentialSlots() {
        let items = NetworkLister.items(
            networkVolumes: [volume("Zeta"), volume("alpha")],
            cloudRoots: [cloud("OneDrive"), cloud("Box")])
        // Network shares (sorted) first, then cloud roots (sorted).
        XCTAssertEqual(items.map(\.displayName), ["alpha", "Zeta", "Box", "OneDrive"])
        XCTAssertEqual(items.map(\.slot), [0, 1, 2, 3])
        XCTAssertEqual(items.map(\.kind), [.disk, .disk, .folder, .folder])
    }

    func testItemsCarryURLThatResolves() throws {
        let share = volume("Server")
        let item = try XCTUnwrap(NetworkLister.items(networkVolumes: [share], cloudRoots: []).first)
        XCTAssertEqual(item.url, share.url)
        XCTAssertEqual(BookmarkResolver.url(for: item), share.url)
    }

    func testNonNetworkTabReturnsEmpty() {
        let tab = Tab(title: "I", colorHex: "#0A84FF",
                      anchor: ScreenAnchor(displayUUID: "D", edge: .right, position: 0.5),
                      kind: .items)
        XCTAssertTrue(NetworkLister.contents(of: tab).isEmpty)
    }

    func testCloudRootsReadsFromInjectedHome() throws {
        // A temp "home" with a CloudStorage provider and an iCloud Drive folder.
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let provider = home.appendingPathComponent("Library/CloudStorage/Dropbox", isDirectory: true)
        let iCloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        try fm.createDirectory(at: provider, withIntermediateDirectories: true)
        try fm.createDirectory(at: iCloud, withIntermediateDirectories: true)
        // A stray file directly under CloudStorage must be ignored (only directories
        // are roots). It isn't hidden, so it would be enumerated but rejected as a
        // non-directory.
        try Data().write(to: home.appendingPathComponent("Library/CloudStorage/notes.txt"))
        defer { try? fm.removeItem(at: home) }

        let roots = NetworkLister.cloudRoots(home: home)
        XCTAssertEqual(Set(roots.map(\.name)), ["iCloud Drive", "Dropbox"])
    }
}
