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

    init(openOnHover: Bool = false, autoHide: Bool = true, keepOpenAfterLaunch: Bool = false) {
        self.openOnHover = openOnHover
        self.autoHide = autoHide
        self.keepOpenAfterLaunch = keepOpenAfterLaunch
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        openOnHover = try c.decodeIfPresent(Bool.self, forKey: .openOnHover) ?? false
        autoHide = try c.decodeIfPresent(Bool.self, forKey: .autoHide) ?? true
        keepOpenAfterLaunch = try c.decodeIfPresent(Bool.self, forKey: .keepOpenAfterLaunch) ?? false
    }

    private enum CodingKeys: String, CodingKey { case openOnHover, autoHide, keepOpenAfterLaunch }

    static let `default` = TabBehavior()
}
