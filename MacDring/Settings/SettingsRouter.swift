import Foundation
import Combine

/// Which Settings pane is showing.
enum SettingsSection: Hashable {
    case general, appearance, tabs, about
}

/// Drives Settings navigation so "Configure Tab…" can open straight to a tab.
final class SettingsRouter: ObservableObject {
    @Published var section: SettingsSection = .general
    /// When set, the Tabs pane selects this tab.
    @Published var tabToSelect: UUID?

    func showTab(_ id: UUID) {
        section = .tabs
        tabToSelect = id
    }
}
