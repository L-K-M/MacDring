import Foundation

/// A screen-edge tab and the drawer of items behind it. The unit of the whole
/// app: a colored pill on an edge that expands into a grid/list of launchables.
struct Tab: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    /// The tab's color (`#RRGGBB`). The marquee per-tab customization.
    var colorHex: String
    var glyph: TabGlyph
    var anchor: ScreenAnchor
    var items: [DrawerItem]
    var behavior: TabBehavior
    var hotkey: HotkeySpec?

    /// The drawer's grid size for this tab (width = columns, height = rows). Items
    /// are placed within this grid; it grows if items are placed beyond it.
    var gridColumns: Int
    var gridRows: Int

    /// When locked, the tab can't be dragged to a new position.
    var locked: Bool

    init(id: UUID = UUID(),
         title: String,
         colorHex: String,
         glyph: TabGlyph = .default,
         anchor: ScreenAnchor,
         items: [DrawerItem] = [],
         behavior: TabBehavior = .default,
         hotkey: HotkeySpec? = nil,
         gridColumns: Int = 4,
         gridRows: Int = 2,
         locked: Bool = false) {
        self.id = id
        self.title = title
        self.colorHex = colorHex
        self.glyph = glyph
        self.anchor = anchor
        self.items = items
        self.behavior = behavior
        self.hotkey = hotkey
        self.gridColumns = gridColumns
        self.gridRows = gridRows
        self.locked = locked
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Tab"
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "#0A84FF"
        glyph = try c.decodeIfPresent(TabGlyph.self, forKey: .glyph) ?? .default
        anchor = try c.decode(ScreenAnchor.self, forKey: .anchor)
        items = try c.decodeIfPresent([DrawerItem].self, forKey: .items) ?? []
        behavior = try c.decodeIfPresent(TabBehavior.self, forKey: .behavior) ?? .default
        hotkey = try c.decodeIfPresent(HotkeySpec.self, forKey: .hotkey)
        gridColumns = max(1, try c.decodeIfPresent(Int.self, forKey: .gridColumns) ?? 4)
        gridRows = max(1, try c.decodeIfPresent(Int.self, forKey: .gridRows) ?? 2)
        locked = try c.decodeIfPresent(Bool.self, forKey: .locked) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, colorHex, glyph, anchor, items, behavior, hotkey, gridColumns, gridRows, locked
    }
}
