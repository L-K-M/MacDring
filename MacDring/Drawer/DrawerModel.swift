import AppKit
import Combine

/// Observable content + callbacks for the shared drawer panel. The
/// `TabController` swaps these values as different tabs' drawers are shown.
final class DrawerModel: ObservableObject {
    @Published var title: String = ""
    @Published var colorHex: String = "#0A84FF"
    @Published var edge: Edge = .right
    @Published var items: [DrawerItem] = []
    @Published var isDropTargeted: Bool = false

    /// The tab's grid size (width = columns, height = rows).
    @Published var columns: Int = 4
    @Published var rows: Int = 2

    /// Whether the open tab is locked (shown as a small lock in the drawer header).
    @Published var locked: Bool = false

    /// What the drawer shows.
    @Published var kind: TabKind = .items
    /// The note text (for `.notes` tabs).
    @Published var notes: String = ""
    /// The linked directory (for `.folder` tabs), used by "Open in Finder".
    @Published var folderURL: URL?

    var onLaunch: ((DrawerItem) -> Void)?
    var onRemoveItem: ((DrawerItem) -> Void)?
    var onRevealItem: ((DrawerItem) -> Void)?
    /// Files were dropped on the drawer: `slot` is the target slot, or -1 for the
    /// background. The controller routes (open-with / move-into / add).
    var onDropFiles: ((_ urls: [URL], _ slot: Int) -> Void)?
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    /// Called when a drag-reorder finishes: place `itemID` at grid `slot`.
    var onPlaceItem: ((_ itemID: UUID, _ slot: Int) -> Void)?
    /// Open this tab's settings (drawer header gear).
    var onOpenSettings: (() -> Void)?
    /// Toggle this tab's locked state (drawer header lock).
    var onToggleLocked: (() -> Void)?
    /// Notes text changed (for `.notes` tabs).
    var onNotesChanged: ((String) -> Void)?
    /// Open the linked directory in Finder (for `.folder` tabs).
    var onOpenFolder: (() -> Void)?

    /// The item occupying a grid slot, if any.
    func item(atSlot slot: Int) -> DrawerItem? {
        items.first { $0.slot == slot }
    }
}
