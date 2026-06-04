import Foundation

/// How a tab's pill behaves when it's idle (drawer closed, cursor away) — a
/// Dock-style "get out of the way" mode. The tab reveals again when the cursor
/// enters the screen-edge zone where it lives. See PLAN.md §13.
enum TabConcealment: String, Codable, CaseIterable, Identifiable {
    /// Always visible, flush to its edge (the default).
    case never
    /// Slide off the edge when idle, leaving a thin sliver as a hover hint;
    /// slide back on edge-hover.
    case hide
    /// Stay in place but dim to a faint sliver of opacity when idle; brighten on
    /// edge-hover. Remains clickable while faded.
    case fade

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .never: return "Always visible"
        case .hide:  return "Auto-hide"
        case .fade:  return "Auto-fade"
        }
    }
}
