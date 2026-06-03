import AppKit
import SwiftUI

// MARK: - NSColor hex support

extension NSColor {
    /// Parses `#RRGGBB` or `#RRGGBBAA` (the leading `#` is optional).
    convenience init?(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("#") { string.removeFirst() }

        guard let value = UInt64(string, radix: 16) else { return nil }

        let r, g, b, a: CGFloat
        switch string.count {
        case 6:
            r = CGFloat((value & 0xFF0000) >> 16) / 255
            g = CGFloat((value & 0x00FF00) >> 8) / 255
            b = CGFloat(value & 0x0000FF) / 255
            a = 1
        case 8:
            r = CGFloat((value & 0xFF00_0000) >> 24) / 255
            g = CGFloat((value & 0x00FF_0000) >> 16) / 255
            b = CGFloat((value & 0x0000_FF00) >> 8) / 255
            a = CGFloat(value & 0x0000_00FF) / 255
        default:
            return nil
        }
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }

    /// `#RRGGBB` representation in the sRGB color space.
    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - SwiftUI Color bridging

extension Color {
    /// Creates a `Color` from a `#RRGGBB[AA]` string, falling back to clear.
    init(hexString: String) {
        self = Color(nsColor: NSColor(hex: hexString) ?? .clear)
    }

    /// The hex string for this color (best-effort via `NSColor`).
    var hexString: String {
        NSColor(self).hexString
    }
}
