import AppKit

/// The translucent material behind a drawer (and tab pills). Maps to
/// `NSVisualEffectView.Material`.
enum DrawerMaterial: String, Codable, CaseIterable, Identifiable {
    case sidebar, menu, popover, hud

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sidebar: return "Sidebar"
        case .menu: return "Menu"
        case .popover: return "Popover"
        case .hud: return "HUD"
        }
    }

    var nsMaterial: NSVisualEffectView.Material {
        switch self {
        case .sidebar: return .sidebar
        case .menu: return .menu
        case .popover: return .popover
        case .hud: return .hudWindow
        }
    }
}

/// How drawer items are arranged.
enum DrawerLayout: String, Codable, CaseIterable, Identifiable {
    case grid, list
    var id: String { rawValue }
    var displayName: String { self == .grid ? "Grid" : "List" }
}

/// The visual treatment of tab pills: a sleek translucent rounded pill, or the
/// skeuomorphic angled "folder tab" reminiscent of classic DragThing.
enum TabStyle: String, Codable, CaseIterable, Identifiable {
    case modern, classic
    var id: String { rawValue }
    var displayName: String { self == .modern ? "Modern" : "Classic" }
}

/// What happens to a tab when its display is disconnected (see PLAN.md §6).
enum DisconnectPolicy: String, Codable, CaseIterable, Identifiable {
    /// Hide the tab and keep its anchor; restore it exactly when the display returns.
    case park
    /// Move the tab to the main display so it stays visible.
    case moveToMain
    var id: String { rawValue }
    var displayName: String { self == .park ? "Keep them on that display" : "Move them to the main display" }
}

/// The window level tabs float at.
enum TabWindowLevel: String, Codable, CaseIterable, Identifiable {
    case floating, normal
    var id: String { rawValue }
    var displayName: String { self == .floating ? "Always on top" : "With other windows" }

    var nsWindowLevel: NSWindow.Level {
        self == .floating ? .floating : .normal
    }
}
