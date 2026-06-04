import AppKit
import Combine

/// Observable content + callbacks for the shared drawer panel. The
/// `TabController` swaps these values as different tabs' drawers are shown.
final class DrawerModel: ObservableObject {
    @Published var title: String = ""
    @Published var colorHex: String = "#0A84FF"
    @Published var edge: Edge = .right
    /// Inner corners to square so the riding tab joins the drawer flush (set by the
    /// window controller from the tab/drawer geometry). `start`/`end` run along the
    /// inward face: top→bottom for left/right, leading→trailing for top/bottom.
    @Published var squareInnerStart: Bool = false
    @Published var squareInnerEnd: Bool = false
    @Published var items: [DrawerItem] = []
    @Published var isDropTargeted: Bool = false
    /// The grid slot a file drag is currently hovering over (drives the per-slot
    /// drop highlight while spring-loaded). `nil` when no slot is targeted.
    @Published var fileDropSlot: Int?
    /// Slot → cell frame (in the drawer's content coordinate space), mirrored from
    /// the view so the file-drop delegate can map a drag location to a slot **live**.
    /// (The delegate's own captured copy is stale when a drawer springs open
    /// mid-drag, before the grid has reported its frames.)
    var slotFrames: [Int: CGRect] = [:]

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

    /// Bumped to force drawer item icons to re-resolve in place even though the
    /// items are unchanged — e.g. the Trash icon (full → empty) after emptying.
    @Published var iconNonce = 0

    var onLaunch: ((DrawerItem) -> Void)?
    var onRemoveItem: ((DrawerItem) -> Void)?
    var onRevealItem: ((DrawerItem) -> Void)?
    /// Empty the Trash (Trash item context menu).
    var onEmptyTrash: (() -> Void)?
    /// Rename an item (drawer item context menu).
    var onRenameItem: ((DrawerItem) -> Void)?
    /// Choose a custom icon image for an item.
    var onChangeItemIcon: ((DrawerItem) -> Void)?
    /// Clear an item's custom icon, restoring its default.
    var onResetItemIcon: ((DrawerItem) -> Void)?
    /// Eject a `.disk` item's volume (Disks tab).
    var onEjectItem: ((DrawerItem) -> Void)?
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
