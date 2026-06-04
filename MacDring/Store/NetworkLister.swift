import Foundation

/// Lists the user's **network shares** and **cloud-storage drives** for a
/// `.network` tab as transient `DrawerItem`s (never stored in the document —
/// re-read live each time the drawer opens, like `FolderLister`/`DisksLister`).
///
/// Two sources, both surfaced read-only:
/// - **Network shares** — mounted *remote* volumes (SMB / AFP / NFS / WebDAV / …).
///   These are real volumes, so they're listed as `.disk` items: click to open in
///   Finder, **eject** (a Finder-style "disconnect") from the item's menu. Local
///   disks, USB media, and mounted disk images are excluded — those are the Disks
///   tab's job.
/// - **Cloud drives** — iCloud Drive and the File-Provider providers macOS keeps
///   under `~/Library/CloudStorage` (Dropbox, Google Drive, OneDrive, Box, …).
///   These are folders, not volumes, so they're listed as `.folder` items: click
///   to open in Finder (they can't be ejected).
enum NetworkLister {
    /// Cap so an unusual machine with many mounts/providers can't blow up the drawer.
    static let limit = 100

    /// A mounted volume's relevant properties, split out from `FileManager` so the
    /// filter/sort/map below is pure and unit-testable on its own.
    struct Volume: Equatable {
        let url: URL
        let name: String
        let isLocal: Bool
        let isBrowsable: Bool
    }

    /// A cloud-storage root (iCloud Drive or a `~/Library/CloudStorage` provider).
    struct CloudRoot: Equatable {
        let url: URL
        let name: String
    }

    /// The tab's network shares and cloud drives as launchable items (empty if not a
    /// network tab or nothing is mounted/available).
    static func contents(of tab: Tab) -> [DrawerItem] {
        guard tab.kind == .network else { return [] }
        return items(networkVolumes: mountedVolumes(), cloudRoots: cloudRoots())
    }

    /// Pure: the network shares (sorted by name) as ejectable `.disk` items, then the
    /// cloud roots (sorted by name) as `.folder` items, with sequential grid slots.
    static func items(networkVolumes: [Volume], cloudRoots: [CloudRoot]) -> [DrawerItem] {
        let shares = networkVolumes.filter(isNetwork).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }.map { DrawerItem(kind: .disk, displayName: $0.name, url: $0.url) }

        let clouds = cloudRoots.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }.map { DrawerItem(kind: .folder, displayName: $0.name, url: $0.url) }

        return (shares + clouds).prefix(limit).enumerated().map { index, item in
            var item = item
            item.slot = index
            return item
        }
    }

    /// A mounted volume is a "network share" when it's user-visible and **not local**
    /// — a remote SMB / AFP / NFS / WebDAV mount. Local disks, USB media, and mounted
    /// disk images report `isLocal == true`, so they're excluded (the Disks tab lists
    /// those).
    static func isNetwork(_ volume: Volume) -> Bool {
        volume.isBrowsable && !volume.isLocal
    }

    // MARK: FileManager bridge

    private static let keys: [URLResourceKey] = [
        .volumeNameKey, .volumeLocalizedNameKey, .volumeIsLocalKey, .volumeIsBrowsableKey,
    ]

    private static func mountedVolumes() -> [Volume] {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap(volume(at:))
    }

    private static func volume(at url: URL) -> Volume? {
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
        let name = values.volumeLocalizedName
            ?? values.volumeName
            ?? FileManager.default.displayName(atPath: url.path)
        return Volume(
            url: url,
            name: name,
            // A volume that doesn't report locality is assumed local, so it can't
            // masquerade as a network share; one that doesn't report browsability is
            // assumed visible (it came back from a `skipHiddenVolumes` enumeration).
            isLocal: values.volumeIsLocal ?? true,
            isBrowsable: values.volumeIsBrowsable ?? true
        )
    }

    // MARK: Cloud storage

    /// iCloud Drive plus the File-Provider cloud providers macOS keeps under
    /// `~/Library/CloudStorage` (Dropbox, Google Drive, OneDrive, Box, …). Reads only
    /// the user's own Library — no special permission — and degrades to an empty list
    /// if a directory can't be read. `home` is injectable for tests.
    static func cloudRoots(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                           fileManager: FileManager = .default) -> [CloudRoot] {
        var roots: [CloudRoot] = []

        let iCloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        if fileManager.fileExists(atPath: iCloud.path) {
            roots.append(CloudRoot(url: iCloud, name: "iCloud Drive"))
        }

        let cloudStorage = home.appendingPathComponent("Library/CloudStorage", isDirectory: true)
        if let entries = try? fileManager.contentsOfDirectory(
            at: cloudStorage,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]) {
            for entry in entries {
                let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                guard isDir else { continue }
                let display = fileManager.displayName(atPath: entry.path)
                roots.append(CloudRoot(url: entry, name: display.isEmpty ? entry.lastPathComponent : display))
            }
        }
        return roots
    }
}
