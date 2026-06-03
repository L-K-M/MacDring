import Foundation

/// The persisted root: the full set of tabs and their items. Stored as JSON in
/// Application Support (see `TabStore`). The `version` field drives forward
/// migrations if the schema changes.
struct LauncherDocument: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var tabs: [Tab]

    init(version: Int = LauncherDocument.currentVersion, tabs: [Tab] = []) {
        self.version = version
        self.tabs = tabs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? LauncherDocument.currentVersion
        tabs = try c.decodeIfPresent([Tab].self, forKey: .tabs) ?? []
    }

    private enum CodingKeys: String, CodingKey { case version, tabs }

    static let empty = LauncherDocument(tabs: [])
}
