import Foundation

/// Lists **newly arrived** files — recently downloaded, copied, or saved — for a
/// `.fresh` tab, as transient `DrawerItem`s (never stored in the document; gathered
/// live each time the drawer opens, like the other listers). The data comes from
/// Spotlight via `SpotlightQuery` (ranked by `kMDItemDateAdded`); this is the pure
/// part — turning those results into ordered, slotted drawer items.
///
/// Named after the classic "Fresh"-style utilities that surface the file you just
/// grabbed so you don't have to go hunting for where it landed.
enum FreshLister {
    /// Cap so a busy Downloads folder can't blow up the drawer.
    static let limit = 40

    /// Newly-arrived files as launchable items, most-recently-added first, with
    /// sequential grid slots.
    static func items(from results: [SpotlightQuery.Result]) -> [DrawerItem] {
        let newestFirst = results.sorted { $0.date > $1.date }
        return newestFirst.prefix(limit).enumerated().map { index, result in
            // Transient items skip the per-file bookmark — never persisted, and every
            // read path falls back to `url`. See ANALYSIS.md I1 / FolderLister.
            var item = DrawerItem.transientFileItem(result.url)
            item.slot = index
            return item
        }
    }

    /// The directories a Fresh tab scans: the usual landing zones for new files.
    /// Reading them via Spotlight needs no special permission, and a missing folder
    /// simply contributes nothing. `home` is injectable for tests.
    static func scopes(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        ["Downloads", "Desktop", "Documents"].map {
            home.appendingPathComponent($0, isDirectory: true)
        }
    }
}
