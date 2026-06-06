import Foundation

/// How a `.folder` tab orders its live listing. Folders always sort before files;
/// this picks the order *within* each group.
enum FolderSort: String, Codable, CaseIterable, Identifiable {
    /// A → Z by name (the default).
    case name
    /// Most recently modified first.
    case dateModified
    /// Grouped by file extension, then by name.
    case kind

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .name: return "Name"
        case .dateModified: return "Date Modified"
        case .kind: return "Kind"
        }
    }
}
