import Foundation

/// A screen edge that a tab can be anchored to.
enum Edge: String, Codable, CaseIterable, Identifiable {
    case left, right, top, bottom

    var id: String { rawValue }

    /// Edges where tabs run along the vertical axis (the pill is tall and thin,
    /// flush to a left/right side). The complement runs along the horizontal axis.
    var isVertical: Bool { self == .left || self == .right }

    var displayName: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        case .top: return "Top"
        case .bottom: return "Bottom"
        }
    }
}
