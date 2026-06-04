import Foundation

/// Per-tab interaction behavior. Defaults are seeded from `Preferences` when a
/// new tab is created, then editable per tab.
struct TabBehavior: Codable, Equatable {

    /// Open the drawer on hover instead of requiring a click.
    var openOnHover: Bool

    /// Close the drawer automatically when focus leaves it. (Clicking outside or
    /// pressing Esc always closes it regardless.)
    var autoHide: Bool

    /// Keep the drawer open after launching an item instead of closing it.
    var keepOpenAfterLaunch: Bool

    /// How the tab's pill conceals itself when idle (Dock-style auto-hide /
    /// auto-fade), revealing on screen-edge hover. Distinct from `autoHide`, which
    /// governs the *drawer*. See `TabConcealment`.
    var concealment: TabConcealment

    init(openOnHover: Bool = false, autoHide: Bool = true, keepOpenAfterLaunch: Bool = false,
         concealment: TabConcealment = .never) {
        self.openOnHover = openOnHover
        self.autoHide = autoHide
        self.keepOpenAfterLaunch = keepOpenAfterLaunch
        self.concealment = concealment
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        openOnHover = try c.decodeIfPresent(Bool.self, forKey: .openOnHover) ?? false
        autoHide = try c.decodeIfPresent(Bool.self, forKey: .autoHide) ?? true
        keepOpenAfterLaunch = try c.decodeIfPresent(Bool.self, forKey: .keepOpenAfterLaunch) ?? false
        concealment = try c.decodeIfPresent(TabConcealment.self, forKey: .concealment) ?? .never
    }

    private enum CodingKeys: String, CodingKey { case openOnHover, autoHide, keepOpenAfterLaunch, concealment }

    static let `default` = TabBehavior()
}
