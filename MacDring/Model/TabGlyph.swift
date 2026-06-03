import Foundation

/// The mark shown on a tab's pill. Either an SF Symbol or a short monogram
/// (1–2 letters). Encoded as `{ "kind": ..., "value": ... }` for a stable,
/// human-readable JSON shape.
enum TabGlyph: Codable, Equatable {
    case symbol(String)    // SF Symbol name, e.g. "folder.fill"
    case monogram(String)  // 1–2 letters, e.g. "W"

    static let `default` = TabGlyph.symbol("square.grid.2x2.fill")

    private enum CodingKeys: String, CodingKey { case kind, value }
    private enum Kind: String, Codable { case symbol, monogram }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        let value = try c.decode(String.self, forKey: .value)
        switch kind {
        case .symbol: self = .symbol(value)
        case .monogram: self = .monogram(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .symbol(let v):
            try c.encode(Kind.symbol, forKey: .kind)
            try c.encode(v, forKey: .value)
        case .monogram(let v):
            try c.encode(Kind.monogram, forKey: .kind)
            try c.encode(v, forKey: .value)
        }
    }
}
