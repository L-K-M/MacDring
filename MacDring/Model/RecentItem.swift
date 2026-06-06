import Foundation

/// A target recently opened from MacDring — the backing record for a `.recents` tab.
/// Tracked by MacDring itself (every drawer launch) rather than the system's recent
/// items, so it needs no special permission and no deprecated `LSSharedFileList`.
struct RecentItem: Codable, Equatable {
    /// The openable target (app/file/folder/cloud URL, or a web link).
    var url: URL
    var kind: ItemKind
    var name: String
    var date: Date
}
