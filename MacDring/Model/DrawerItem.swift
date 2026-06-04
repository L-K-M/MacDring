import Foundation

/// What a drawer item points at.
enum ItemKind: String, Codable { case application, file, folder, url, trash, disk, cloud }

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

    /// A user-defined generated icon (base shape + color + optional SF Symbol). An
    /// alternative to `customIconBookmark` that needs no file. For live/transient
    /// items it's filled in from the owning `Tab.iconStyles` at list time.
    var iconStyle: IconStyle?

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
         iconStyle: IconStyle? = nil,
         slot: Int = -1) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.bookmark = bookmark
        self.url = url
        self.customIconBookmark = customIconBookmark
        self.iconStyle = iconStyle
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
        iconStyle = try c.decodeIfPresent(IconStyle.self, forKey: .iconStyle)
        slot = try c.decodeIfPresent(Int.self, forKey: .slot) ?? -1
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, displayName, bookmark, url, customIconBookmark, iconStyle, slot
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

    /// Applies a tab's per-target icon overrides to these (typically live/transient)
    /// items, keyed by each item's path. Used by the folder/disks/network/cloud
    /// listings, whose items are rebuilt each open and so can't carry the override
    /// themselves. A no-op when the tab has no overrides.
    func applyingIconStyles(from styles: [String: IconStyle]) -> [DrawerItem] {
        guard !styles.isEmpty else { return self }
        return map { item in
            guard let path = item.url?.path, let style = styles[path] else { return item }
            var item = item
            item.iconStyle = style
            return item
        }
    }
}

extension DrawerItem {
    /// Detects an item's kind (app / folder / file) and display name from a
    /// file/app/folder URL — the shared part of `fromFileURL` and `transientFileItem`.
    static func kindAndName(for url: URL) -> (kind: ItemKind, name: String) {
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
        return (kind, name)
    }

    /// Builds an item from a dropped or chosen file, app, or folder URL, detecting the
    /// kind and **capturing a bookmark** so it keeps working when the target is moved
    /// or renamed. Use for items that are **persisted** (drops, the Settings picker).
    static func fromFileURL(_ url: URL) -> DrawerItem {
        let (kind, name) = kindAndName(for: url)
        return DrawerItem(
            kind: kind,
            displayName: name,
            bookmark: BookmarkResolver.makeBookmark(for: url),
            url: url
        )
    }

    /// Builds a lightweight, **transient** item for a live listing (e.g. a folder
    /// tab): detects the kind + name but **skips the bookmark**. Folder items are
    /// never persisted, and every read path (`launch`, `reveal`, `isBroken`, drag-out)
    /// falls back to `url` when there's no bookmark — so this avoids ~N
    /// `makeBookmark` syscalls per refresh on a large directory. See ANALYSIS.md I1.
    static func transientFileItem(_ url: URL) -> DrawerItem {
        let (kind, name) = kindAndName(for: url)
        return DrawerItem(kind: kind, displayName: name, url: url)
    }

    /// Builds an item from a **dropped** URL: a file/app/folder item for file URLs,
    /// or a `.url` link item for web (and other non-file) URLs — so dragging a link
    /// out of a browser onto a tab/drawer adds it, just like dropping a file does.
    static func fromDroppedURL(_ url: URL) -> DrawerItem {
        guard url.isFileURL else {
            return DrawerItem(kind: .url, displayName: url.host ?? url.absoluteString, url: url)
        }
        return fromFileURL(url)
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
