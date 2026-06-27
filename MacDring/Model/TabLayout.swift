import Foundation

/// A tab's drawer layout choice: follow the global default (Appearance → Layout), or
/// pin **grid** or **list** for this tab. The three-way per-tab override mirrors the
/// hover / close-on-click behavior overrides — `useGlobal` is the revert.
enum TabLayout: String, Codable, CaseIterable, Identifiable {
    /// Follow `Preferences.drawerLayout`.
    case useGlobal
    case grid
    case list

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .useGlobal: return "Use global default"
        case .grid: return "Grid"
        case .list: return "List"
        }
    }

    /// The concrete layout to render with: the global default when this tab follows it,
    /// otherwise the pinned choice.
    func resolved(default globalDefault: DrawerLayout) -> DrawerLayout {
        switch self {
        case .useGlobal: return globalDefault
        case .grid: return .grid
        case .list: return .list
        }
    }
}
