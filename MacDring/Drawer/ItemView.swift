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

    @State private var icon: NSImage?

    private var isBroken: Bool { BookmarkResolver.isBroken(item) }

    var body: some View {
        cell
            .opacity(isBroken ? 0.45 : 1)
            .contentShape(Rectangle())
            // ⌘-click reveals the target in Finder instead of opening it (Finder-style).
            .onTapGesture(count: launchOnSingleClick ? 1 : 2) {
                if NSEvent.modifierFlags.contains(.command), item.kind != .url {
                    onReveal()
                } else {
                    onLaunch()
                }
            }
            .help(isBroken ? "\(item.displayName) — can’t find this item" : item.displayName)
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
                        .disabled(ItemView.trashIsEmpty())
                }
                if onRename != nil || onChangeIcon != nil {
                    Divider()
                    if let onRename { Button("Rename…", action: onRename) }
                    if let onChangeIcon { Button("Change Icon…", action: onChangeIcon) }
                    if item.customIconBookmark != nil, let onResetIcon {
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
            .task(id: IconKey(item: item, nonce: iconNonce)) { icon = ItemView.resolveIcon(item) }
    }

    /// Re-resolve key: the item plus the drawer's nonce.
    private struct IconKey: Equatable { let item: DrawerItem; let nonce: Int }

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
            HStack(spacing: 9) {
                iconImage
                Text(item.displayName).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
            }
        }
    }

    private var iconImage: some View {
        Image(nsImage: icon ?? ItemView.resolveIcon(item))
            .resizable()
            .interpolation(.high)
            .frame(width: iconSize, height: iconSize)
    }

    // MARK: Icon resolution

    static func resolveIcon(_ item: DrawerItem) -> NSImage {
        // A user-chosen icon override wins over the target's own icon.
        if let data = item.customIconBookmark,
           let resolved = BookmarkResolver.resolve(data),
           let custom = NSImage(contentsOf: resolved.url) {
            return custom
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
    private static func trashIcon() -> NSImage {
        NSImage(named: trashIsEmpty() ? "NSTrashEmpty" : "NSTrashFull") ?? symbol("trash")
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

    /// Whether the Trash is empty, decided **without listing it** (it's
    /// privacy-protected, so a list fails without a permission we don't request).
    /// We stat the directory instead (always allowed): on APFS a directory's link
    /// count is its entry count + 2, so a count of 2 means empty. If even the stat
    /// fails we assume non-empty (a recognizable Trash) rather than guess empty.
    static func trashIsEmpty() -> Bool {
        let trash = (try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash", isDirectory: true)
        let attrs = try? FileManager.default.attributesOfItem(atPath: trash.path)
        let linkCount = (attrs?[.referenceCount] as? NSNumber)?.intValue
        return linkCount == 2
    }

    private static func symbol(_ name: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
    }
}
