import Foundation

/// Lists the recently-opened targets for a `.recents` tab as transient `DrawerItem`s
/// (never stored in the document — re-read live each time the drawer opens, like the
/// other listers). The data comes from `RecentsStore`; click an item to re-open it.
enum RecentsLister {
    /// The tab's recent items as launchable items, most-recent first (empty if not a
    /// recents tab or nothing has been opened yet).
    static func contents(of tab: Tab, store: RecentsStore = .shared) -> [DrawerItem] {
        guard tab.kind == .recents else { return [] }
        return store.items.prefix(RecentsStore.limit).enumerated().map { index, recent in
            DrawerItem(kind: recent.kind, displayName: recent.name, url: recent.url, slot: index)
        }
    }
}
