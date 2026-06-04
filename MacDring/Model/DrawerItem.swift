import Foundation

/// What a drawer item points at.
enum ItemKind: String, Codable { case application, file, folder, url, trash }

/// A single launchable entry inside a drawer: an app, file, folder, or URL.
///
/// Apps/files/folders are tracked by a URL **bookmark** so the item keeps
/// working when the target is moved or renamed. `.url` items store the link in
/// `url`. See PLAN.md §4.
struct DrawerItem: Codable, Identifiable, Equatable {
    var id: UUID
    var kind: ItemKind
    var displayName: String

    /// Bookmark to the app/file/folder target; `nil` for `.url` items.
    var bookmark: Data?

    /// The link for `.url` items (also a resolved-path fallback for others).
    var url: URL?

    /// Optional icon override (bookmark to an image file).
    var customIconBookmark: Data?

    /// The item's position in the drawer's grid (row-major linear index). Lets
    /// items be arranged freely with gaps. `-1` means "unassigned" — `TabStore`
    /// fills it with the lowest free slot (used for new items and migration).
    var slot: Int

    init(id: UUID = UUID(),
         kind: ItemKind,
         displayName: String,
         bookmark: Data? = nil,
         url: URL? = nil,
         customIconBookmark: Data? = nil,
         slot: Int = -1) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.bookmark = bookmark
        self.url = url
        self.customIconBookmark = customIconBookmark
        self.slot = slot
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decode(ItemKind.self, forKey: .kind)
        displayName = try c.decode(String.self, forKey: .displayName)
        bookmark = try c.decodeIfPresent(Data.self, forKey: .bookmark)
        url = try c.decodeIfPresent(URL.self, forKey: .url)
        customIconBookmark = try c.decodeIfPresent(Data.self, forKey: .customIconBookmark)
        slot = try c.decodeIfPresent(Int.self, forKey: .slot) ?? -1
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, displayName, bookmark, url, customIconBookmark, slot
    }
}

extension Array where Element == DrawerItem {
    /// Returns the items with every `slot` valid and distinct: existing valid
    /// slots are kept (preserving gaps), while unassigned (`-1`) or duplicate
    /// slots are filled with the lowest free slots, in array order.
    func assigningMissingSlots() -> [DrawerItem] {
        var used = Set<Int>()
        var result = self
        for i in result.indices {
            let slot = result[i].slot
            if slot >= 0, used.insert(slot).inserted { continue }
            result[i].slot = -1   // unassigned or a duplicate
        }
        var next = 0
        for i in result.indices where result[i].slot < 0 {
            while used.contains(next) { next += 1 }
            result[i].slot = next
            used.insert(next)
        }
        return result
    }
}

extension DrawerItem {
    /// Builds an item from a dropped or chosen file, app, or folder URL,
    /// detecting the kind and capturing a bookmark.
    static func fromFileURL(_ url: URL) -> DrawerItem {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        let kind: ItemKind
        if url.pathExtension.lowercased() == "app" {
            kind = .application
        } else if isDirectory.boolValue {
            kind = .folder
        } else {
            kind = .file
        }
        var name = FileManager.default.displayName(atPath: url.path)
        // Apps shouldn't show the ".app" extension (Finder hides it; `displayName`
        // includes it when "show all extensions" is on).
        if kind == .application, name.lowercased().hasSuffix(".app") {
            name = String(name.dropLast(4))
        }
        if name.isEmpty { name = url.deletingPathExtension().lastPathComponent }
        return DrawerItem(
            kind: kind,
            displayName: name,
            bookmark: BookmarkResolver.makeBookmark(for: url),
            url: url
        )
    }

    /// A Trash item: opens the Trash in Finder when clicked, and deletes (moves to
    /// Trash) any files dropped onto it — the classic DragThing Trash dock.
    static func trash() -> DrawerItem {
        let url = (try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash", isDirectory: true)
        return DrawerItem(kind: .trash, displayName: "Trash", url: url)
    }

    /// Builds a `.url` item from a typed link, defaulting a missing scheme to https.
    /// Returns `nil` if the string can't form a URL.
    static func fromLink(_ string: String) -> DrawerItem? {
        var trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains("://") { trimmed = "https://" + trimmed }
        guard let url = URL(string: trimmed), url.scheme != nil else { return nil }
        return DrawerItem(kind: .url, displayName: url.host ?? trimmed, url: url)
    }
}
