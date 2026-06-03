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
        // Decode tabs leniently: a single malformed tab (e.g. a missing/corrupt
        // anchor) must not throw away the *entire* document — an arranged launcher
        // is "sacred" (PLAN §2/§6). Each element is decoded through a non-throwing
        // wrapper, so a bad record is dropped while the rest survive.
        let wrapped = try c.decodeIfPresent([FailableTab].self, forKey: .tabs) ?? []
        tabs = wrapped.compactMap(\.tab)
    }

    private enum CodingKeys: String, CodingKey { case version, tabs }

    static let empty = LauncherDocument(tabs: [])
}

/// Decodes a single `Tab` without throwing: an unreadable element yields `nil`
/// (and is filtered out) rather than failing the whole `[Tab]` decode. Using a
/// wrapper — instead of `try?` inside an unkeyed container — keeps the container's
/// index advancing past a bad element, which a thrown error would not.
private struct FailableTab: Decodable {
    let tab: Tab?

    init(from decoder: Decoder) throws {
        tab = try? Tab(from: decoder)
    }
}
