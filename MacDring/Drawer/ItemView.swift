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
                Button("Open", action: onLaunch)
                if item.kind != .url {
                    Button("Reveal in Finder", action: onReveal)
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
            // Keyed by the whole `item`: loads on appear AND reloads whenever the
            // item changes — a reorder swap into this (slot-keyed, reused) cell, a
            // rename, or a custom-icon change — so the icon always follows the item.
            .task(id: item) { icon = ItemView.resolveIcon(item) }
    }

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
    ///
    /// The Trash is privacy-protected, so *listing* it fails without a permission
    /// we deliberately don't request. Instead we **stat** the directory (always
    /// allowed): on APFS a directory's link count is its entry count + 2, so a
    /// count greater than 2 means the Trash isn't empty. If even the stat fails we
    /// show the full can (a recognizable Trash) rather than guess empty.
    private static func trashIcon() -> NSImage {
        let trash = (try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash", isDirectory: true)
        let attrs = try? FileManager.default.attributesOfItem(atPath: trash.path)
        let linkCount = (attrs?[.referenceCount] as? NSNumber)?.intValue
        let isEmpty = linkCount == 2
        return NSImage(named: isEmpty ? "NSTrashEmpty" : "NSTrashFull") ?? symbol("trash")
    }

    private static func symbol(_ name: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
    }
}
