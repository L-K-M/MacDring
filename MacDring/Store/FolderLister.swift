import Foundation

/// Lists a folder tab's linked directory as transient `DrawerItem`s (not stored
/// in the document). Skips hidden files; folders sort before files, then
/// alphabetically. Capped so a huge directory can't blow up the drawer.
enum FolderLister {
    static let limit = 300

    /// The directory a `.folder` tab points at, or `nil` if unset/unresolvable.
    static func resolveFolder(_ tab: Tab) -> URL? {
        if let data = tab.folderBookmark, let resolved = BookmarkResolver.resolve(data) {
            return resolved.url
        }
        return tab.folderURL
    }

    /// The tab's directory contents as launchable items (empty if not a folder tab
    /// or the directory can't be read).
    static func contents(of tab: Tab) -> [DrawerItem] {
        guard tab.kind == .folder, let url = resolveFolder(tab) else { return [] }
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let sorted = entries.sorted { lhs, rhs in
            let lhsDir = (try? lhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let rhsDir = (try? rhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if lhsDir != rhsDir { return lhsDir }   // directories first
            return lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
        }

        return sorted.prefix(limit).enumerated().map { index, fileURL in
            var item = DrawerItem.fromFileURL(fileURL)
            item.slot = index
            return item
        }
    }
}
