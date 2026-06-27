import SwiftUI
import AppKit

/// One launchable entry inside a drawer — icon + label, with a context menu and
/// single/double-click launch. Broken items (missing target) render dimmed.
struct ItemView: View {
    let item: DrawerItem
    let iconSize: CGFloat
    let layout: DrawerLayout
    let launchOnSingleClick: Bool
    var onLaunch: () -> Void
    var onReveal: () -> Void
    var onRemove: (() -> Void)?
    var onRename: (() -> Void)?
    var onChangeIcon: (() -> Void)?
    var onResetIcon: (() -> Void)?
    var onEmptyTrash: (() -> Void)?
    /// Bumped by the drawer to force a fresh icon even when `item` is unchanged.
    var iconNonce: Int = 0
    var onEject: (() -> Void)?
    /// Open the generated-icon editor for this item (available for every item).
    var onCustomizeIcon: (() -> Void)?
    /// Bundle IDs of currently-running apps — drives the "running" dot on app items.
    var runningBundleIDs: Set<String> = []

    // Icon and broken-ness are resolved off the render path (in `.task`, once per
    // item/nonce change) and cached here, so `body` does no disk I/O on every
    // re-render — important for a large or network-volume folder tab. See ANALYSIS.md I2.
    @State private var icon: NSImage?
    @State private var broken = false
    /// An app item's bundle id (resolved off the render path, like the icon), so the
    /// running dot is a cheap `Set.contains` in `body`.
    @State private var bundleID: String?
    /// File size and localized kind for the list layout's columns, resolved off the
    /// render path (only in list mode). `nil` for folders / non-file items.
    @State private var byteSize: Int64?
    @State private var typeDescription: String?

    /// Finder-style small icon for the list layout, regardless of the grid's icon size.
    static let listIconSize: CGFloat = 16

    /// The icon's rendered size: a fixed small glyph in list mode, the configured size
    /// in grid mode.
    private var effectiveIconSize: CGFloat { layout == .list ? Self.listIconSize : iconSize }

    var body: some View {
        cell
            .opacity(broken ? 0.45 : 1)
            .contentShape(Rectangle())
            // ⌘-click reveals the target in Finder instead of opening it (Finder-style).
            .onTapGesture(count: launchOnSingleClick ? 1 : 2) {
                if NSEvent.modifierFlags.contains(.command), item.kind != .url {
                    onReveal()
                } else {
                    onLaunch()
                }
            }
            .help(broken ? "\(item.displayName) — can’t find this item" : item.displayName)
            .contextMenu {
                Button(item.kind == .disk ? "Open Disk" : "Open", action: onLaunch)
                if item.kind != .url {
                    Button("Reveal in Finder", action: onReveal)
                }
                if let onEject {
                    Divider()
                    Button("Eject", action: onEject)
                }
                if item.kind == .trash, let onEmptyTrash {
                    Divider()
                    Button("Empty Trash…", action: onEmptyTrash)
                        .disabled(TrashInspector.trashIsEmpty())
                }
                if onRename != nil || onChangeIcon != nil || onCustomizeIcon != nil {
                    Divider()
                    if let onRename { Button("Rename…", action: onRename) }
                    if let onCustomizeIcon { Button("Customize Icon…", action: onCustomizeIcon) }
                    if let onChangeIcon { Button("Change Icon…", action: onChangeIcon) }
                    if (item.customIconBookmark != nil || item.iconStyle != nil), let onResetIcon {
                        Button("Reset Icon", action: onResetIcon)
                    }
                }
                if let onRemove {
                    Divider()
                    Button("Remove", role: .destructive, action: onRemove)
                }
            }
            // Keyed by the item AND `iconNonce`: reloads whenever the item changes
            // — a reorder swap into this (slot-keyed, reused) cell, a rename, or a
            // custom-icon change — and whenever the drawer bumps the nonce (e.g. the
            // Trash was emptied), so the icon always follows the item's state.
            .task(id: ResolveKey(item: item, nonce: iconNonce, list: layout == .list)) {
                icon = ItemView.resolveIcon(item)
                broken = BookmarkResolver.isBroken(item)
                bundleID = ItemView.appBundleID(item)
                // The list layout shows size + kind columns; resolve them off the render
                // path too (and only when actually in a list).
                if layout == .list {
                    let meta = ItemView.resolveMetadata(item)
                    byteSize = meta.size
                    typeDescription = meta.kind
                } else {
                    byteSize = nil
                    typeDescription = nil
                }
            }
    }

    /// Re-resolve key: the item, the drawer's nonce, and whether the list columns are
    /// shown (so a grid→list switch re-resolves the metadata).
    private struct ResolveKey: Equatable { let item: DrawerItem; let nonce: Int; let list: Bool }

    @ViewBuilder
    private var cell: some View {
        if layout == .grid {
            VStack(spacing: 5) {
                iconImage
                Text(item.displayName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: iconSize + 28)
            }
        } else {
            // A Finder-style row: small icon + name, then a metadata table (date / size
            // / kind) in fixed columns so they line up down the list. Columns reserve
            // their width even when empty (apps / links have no date or size).
            HStack(spacing: 8) {
                iconImage
                Text(item.displayName)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                metaColumn(item.date.map(ItemView.listDate) ?? "", width: 104, alignment: .trailing)
                metaColumn(byteSize.map(ItemView.listSize) ?? "", width: 52, alignment: .trailing)
                metaColumn(typeDescription ?? "", width: 76, alignment: .leading)
            }
            .font(.system(size: 12))
        }
    }

    /// One metadata column: secondary-colored, fixed width, single line.
    private func metaColumn(_ text: String, width: CGFloat, alignment: Alignment) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: width, alignment: alignment)
    }

    /// A Finder-style date for the list's date column: "Today at 9:03 PM", or
    /// "18 Feb 2026 at 18:22" (locale-aware, with relative day names for recent dates).
    static func listDate(_ date: Date) -> String { listDateFormatter.string(from: date) }

    /// The item's size for the list's size column ("2.2 MB", "811 KB").
    static func listSize(_ bytes: Int64) -> String { sizeFormatter.string(fromByteCount: bytes) }

    private static let listDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true   // "Today" / "Yesterday" where it applies
        return formatter
    }()

    private static let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private var iconImage: some View {
        // Render from the cached icon; until `.task` resolves it (one frame), show a
        // transparent placeholder rather than doing synchronous disk I/O in `body`.
        Image(nsImage: icon ?? ItemView.placeholder)
            .resizable()
            .interpolation(.high)
            .frame(width: effectiveIconSize, height: effectiveIconSize)
            .overlay(alignment: .bottom) { runningDot }
    }

    /// A small green dot on the bottom edge of a **running** app's icon (Dock-style).
    @ViewBuilder
    private var runningDot: some View {
        if isAppRunning {
            let dot = max(4, effectiveIconSize * 0.12)
            Circle()
                .fill(Color.green)
                .overlay(Circle().strokeBorder(.black.opacity(0.25), lineWidth: 0.5))
                .frame(width: dot, height: dot)
                .offset(y: -dot * 0.3)   // mostly inside the icon's lower edge
                .shadow(color: .black.opacity(0.3), radius: 0.5)
        }
    }

    /// Whether this item is a running application (its bundle id is in the live set).
    private var isAppRunning: Bool {
        guard item.kind == .application, let bundleID else { return false }
        return runningBundleIDs.contains(bundleID)
    }

    /// An application item's bundle identifier (read off the render path), or `nil`.
    private static func appBundleID(_ item: DrawerItem) -> String? {
        guard item.kind == .application, let url = BookmarkResolver.url(for: item) else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }

    /// The item's byte size and localized kind ("ZIP archive", "Folder", …) for the
    /// list columns, read off the render path. Size is `nil` for folders / non-file
    /// items (where a single number is meaningless); kind comes from the filesystem.
    private static func resolveMetadata(_ item: DrawerItem) -> (size: Int64?, kind: String?) {
        guard let url = BookmarkResolver.url(for: item) else { return (nil, nil) }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey, .localizedTypeDescriptionKey])
        let isDirectory = values?.isDirectory ?? false
        let size = isDirectory ? nil : values?.fileSize.map(Int64.init)
        return (size, values?.localizedTypeDescription)
    }

    /// A 1×1 transparent image shown for the one frame before `.task` resolves the
    /// real icon (avoids a blocking `resolveIcon` in `body`).
    private static let placeholder = NSImage(size: NSSize(width: 1, height: 1), flipped: false) { _ in true }

    // MARK: Icon resolution

    static func resolveIcon(_ item: DrawerItem) -> NSImage {
        // A user-chosen icon override wins over the target's own icon.
        if let data = item.customIconBookmark,
           let resolved = BookmarkResolver.resolve(data),
           let custom = NSImage(contentsOf: resolved.url) {
            return custom
        }
        // A user-defined generated icon (base shape + color + optional SF Symbol).
        if let style = item.iconStyle {
            return IconRenderer.image(for: style)
        }
        // The Trash shows the system full / empty trash can. Handled before the
        // broken check, since a Trash item has no bookmark of its own.
        if item.kind == .trash {
            return trashIcon()
        }
        // A mounted volume shows its own drive icon. Handled before the broken check
        // so a volume that just unmounted shows a drive glyph for the instant before
        // the live listing drops it, not the broken-item triangle.
        if item.kind == .disk {
            if let url = BookmarkResolver.url(for: item), FileManager.default.fileExists(atPath: url.path) {
                return NSWorkspace.shared.icon(forFile: url.path)
            }
            return symbol("externaldrive")
        }
        // A cloud drive shows a cloud-flavored icon. Handled before the broken check
        // for the same reason as `.disk` (a provider can drop out between re-lists).
        if item.kind == .cloud {
            return cloudIcon(for: item)
        }
        if BookmarkResolver.isBroken(item) {
            return symbol("exclamationmark.triangle")
        }
        switch item.kind {
        case .url:
            return symbol("globe")
        default:
            if let url = BookmarkResolver.url(for: item) {
                return NSWorkspace.shared.icon(forFile: url.path)
            }
            return symbol("questionmark.square.dashed")
        }
    }

    /// The system Trash icon — full when the Trash holds anything, empty otherwise.
    /// Emptiness mirrors Finder across every volume's trash (see `TrashInspector`).
    private static func trashIcon() -> NSImage {
        NSImage(named: TrashInspector.trashIsEmpty() ? "NSTrashEmpty" : "NSTrashFull") ?? symbol("trash")
    }

    /// A cloud-drive's icon: the system iCloud glyph for iCloud Drive (whose raw
    /// folder otherwise reads as a generic folder), and the provider's own folder
    /// icon for third-party providers (Dropbox / Drive / OneDrive set one), falling
    /// back to a cloud glyph when the folder can't be resolved.
    private static func cloudIcon(for item: DrawerItem) -> NSImage {
        guard let url = BookmarkResolver.url(for: item),
              FileManager.default.fileExists(atPath: url.path) else {
            return symbol("cloud.fill")
        }
        if url.path.contains("com~apple~CloudDocs") { return symbol("icloud.fill") }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private static func symbol(_ name: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
    }
}
