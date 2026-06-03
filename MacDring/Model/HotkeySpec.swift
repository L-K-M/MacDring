import Foundation

/// A global hotkey stored as a raw virtual key code plus a Carbon modifier mask,
/// so it can be registered with `RegisterEventHotKey` — which needs **no**
/// Accessibility permission (see PLAN.md §10).
struct HotkeySpec: Codable, Equatable {
    /// Virtual key code (e.g. `kVK_ANSI_M`).
    var keyCode: UInt32
    /// Carbon modifier mask (`cmdKey | optionKey | …`).
    var carbonModifiers: UInt32
}
