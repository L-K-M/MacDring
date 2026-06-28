import Foundation

/// A user-defined **generated** icon for a drawer item: a colored base shape with an
/// optional SF Symbol "burned in". An alternative to a custom image
/// (`DrawerItem.customIconBookmark`) that needs no file — pick a color and a symbol.
///
/// Used two ways:
/// - on a persistent item, stored on `DrawerItem.iconStyle`;
/// - on a live/transient item (folder / disks / network / cloud listings), stored on
///   the owning `Tab.iconStyles`, keyed by the item's path, and re-applied to the
///   freshly-listed item each time the drawer opens.
struct IconStyle: Codable, Equatable {

    /// The base shape the color fills and the glyph sits on.
    enum Base: String, Codable, CaseIterable, Identifiable {
        case folder   // a macOS-style colored folder, glyph embossed on the body
        case tile     // a solid rounded-square tile, glyph centered (app-icon-like)
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .folder: return "Folder"
            case .tile: return "Rounded tile"
            }
        }
    }

    var base: Base
    /// The fill color as `#RRGGBB`.
    var colorHex: String
    /// The SF Symbol burned into the base, or `nil` for a color-only icon.
    var symbol: String?

    init(base: Base = .folder, colorHex: String = "#0A84FF", symbol: String? = nil) {
        self.base = base
        self.colorHex = colorHex
        self.symbol = symbol
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        base = c.decodeLenient(Base.self, forKey: .base, fallback: .folder)
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "#0A84FF"
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol)
    }

    private enum CodingKeys: String, CodingKey { case base, colorHex, symbol }
}
