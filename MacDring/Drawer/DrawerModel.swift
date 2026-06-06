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

    /// Bundle IDs of currently-running apps (kept current by `TabController`), so an
    /// application item shows a Dock-style "running" dot. Updated live as apps
    /// launch/quit.
    @Published var runningBundleIDs: Set<String> = []
    // MARK: Type-to-find

    /// The live filter query (type-to-find). Empty = not searching. Driven by
    /// `TabController`'s key monitor (the borderless panel makes proper text-field
    /// focus unreliable), so this is the single source of truth for the query.
    @Published var searchQuery = ""
    /// The keyboard-selected result while searching (Up/Down/Return nav).
    @Published var selectedItemID: UUID?

    /// Whether this drawer offers search — a non-notes listing with enough items to
    /// be worth filtering. Gates both the search bar and keystroke capture.
    var isSearchable: Bool { kind != .notes && items.count >= DrawerSearch.minItemsToShow }
    var isSearching: Bool { !searchQuery.isEmpty }
    /// The items matching the current query (prefix matches first; see `DrawerSearch`).
    var searchResults: [DrawerItem] { DrawerSearch.filter(items, query: searchQuery) }

    /// Appends typed text to the query and selects the top result.
    func appendSearch(_ text: String) {
        searchQuery += text
        selectedItemID = searchResults.first?.id
    }

    /// Removes the last query character (Delete), re-selecting the top result.
    func deleteSearchCharacter() {
        guard !searchQuery.isEmpty else { return }
        searchQuery.removeLast()
        selectedItemID = searchResults.first?.id
    }

    /// Clears the query and selection (the search bar's ✕, or Esc while searching).
    func clearSearch() {
        searchQuery = ""
        selectedItemID = nil
    }

    /// Moves the keyboard selection among the current results.
    func moveSelection(down: Bool) {
        let ids = searchResults.map(\.id)
        let current = selectedItemID.flatMap { ids.firstIndex(of: $0) }
        if let next = DrawerSearch.nextIndex(count: ids.count, current: current, down: down) {
            selectedItemID = ids[next]
        }
    }

    /// Launches the selected result (Return) — or the top result if none is selected.
    func launchSelection() {
        let results = searchResults
        let target = selectedItemID.flatMap { id in results.first { $0.id == id } } ?? results.first
        if let target { onLaunch?(target) }
    }

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
    /// Open the generated-icon editor for an item (any item, any tab kind).
    var onCustomizeItemIcon: ((DrawerItem) -> Void)?
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
