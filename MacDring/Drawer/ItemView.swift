import SwiftUI

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

    @State private var icon: NSImage?

    private var isBroken: Bool { BookmarkResolver.isBroken(item) }

    var body: some View {
        cell
            .opacity(isBroken ? 0.45 : 1)
            .contentShape(Rectangle())
            .onTapGesture(count: launchOnSingleClick ? 1 : 2, perform: onLaunch)
            .help(isBroken ? "\(item.displayName) — can’t find this item" : item.displayName)
            .contextMenu {
                Button("Open", action: onLaunch)
                if item.kind != .url {
                    Button("Reveal in Finder", action: onReveal)
                }
                if let onRemove {
                    Divider()
                    Button("Remove", role: .destructive, action: onRemove)
                }
            }
            // Keyed by `item.id`: loads on appear AND reloads when a *different*
            // item lands in this (slot-keyed, reused) cell — e.g. a reorder swap —
            // so the icon follows the item instead of staying stale.
            .task(id: item.id) { icon = ItemView.resolveIcon(item) }
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

    private static func symbol(_ name: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
    }
}
