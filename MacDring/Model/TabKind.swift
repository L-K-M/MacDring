import Foundation

/// What a tab's drawer shows.
enum TabKind: String, Codable, CaseIterable, Identifiable {
    /// A freely-arranged grid/list of apps, files, folders, and links (the default).
    case items
    /// A free-text notes area.
    case notes
    /// A live listing of a chosen directory's contents.
    case folder
    /// A live listing of the mounted, ejectable volumes (each openable / ejectable).
    case disks

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .items: return "Items"
        case .notes: return "Notes"
        case .folder: return "Folder"
        case .disks: return "Disks"
        }
    }
}
