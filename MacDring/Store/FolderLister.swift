import Foundation

/// Lists a folder tab's linked directory as transient `DrawerItem`s (not stored in
/// the document). Folders sort before files; the per-tab `folderSort` orders within
/// each group, and `folderShowsHidden` controls whether dotfiles are included. Capped
/// so a huge directory can't blow up the drawer.
enum FolderLister {
    static let limit = 300

    /// The directory a `.folder` tab points at, or `nil` if unset/unresolvable.
    static func resolveFolder(_ tab: Tab) -> URL? {
        if let data = tab.folderBookmark, let resolved = BookmarkResolver.resolve(data) {
            return resolved.url
        }
        return tab.folderURL
    }

    /// A directory entry's sort-relevant properties, read **once** per entry (so the
    /// comparator stays pure and doesn't re-stat on every comparison).
    struct Entry: Equatable {
        let url: URL
        let isDirectory: Bool
        let modified: Date
        var name: String { url.lastPathComponent }
        var ext: String { url.pathExtension.lowercased() }
    }

    /// The tab's directory contents as launchable items (empty if not a folder tab
    /// or the directory can't be read), ordered by the tab's `folderSort`.
    static func contents(of tab: Tab) -> [DrawerItem] {
        guard tab.kind == .folder, let url = resolveFolder(tab) else { return [] }
        let fileManager = FileManager.default
        var options: FileManager.DirectoryEnumerationOptions = []
        if !tab.folderShowsHidden { options.insert(.skipsHiddenFiles) }
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
        guard let urls = try? fileManager.contentsOfDirectory(
            at: url, includingPropertiesForKeys: keys, options: options) else { return [] }

        let entries = urls.map(entry(for:))
        return sorted(entries, by: tab.folderSort).prefix(limit).enumerated().map { index, entry in
            // Transient items skip the per-file bookmark — folder items are never
            // persisted and every read path falls back to `url`. See ANALYSIS.md I1.
            var item = DrawerItem.transientFileItem(entry.url)
            item.slot = index
            item.date = entry.modified   // Date Modified — shown by the list layout
            return item
        }
    }

    /// Pure: folders before files, then the chosen order within each group.
    static func sorted(_ entries: [Entry], by sort: FolderSort) -> [Entry] {
        entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }   // folders on top
            switch sort {
            case .name:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .dateModified:
                if lhs.modified != rhs.modified { return lhs.modified > rhs.modified }   // newest first
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .kind:
                if lhs.ext != rhs.ext { return lhs.ext < rhs.ext }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }

    private static func entry(for url: URL) -> Entry {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
        return Entry(
            url: url,
            isDirectory: values?.isDirectory ?? false,
            modified: values?.contentModificationDate ?? .distantPast
        )
    }
}
