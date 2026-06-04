import SwiftUI

/// A rounded rectangle whose corners facing *into* the screen (away from `edge`)
/// are rounded by `radius`, while the two corners touching the screen edge stay
/// sharp. Used by both the modern tab pill and the open drawer so each reads as
/// emerging flush from the edge.
func edgeRoundedRect(edge: Edge, radius r: CGFloat) -> UnevenRoundedRectangle {
    switch edge {
    case .right:  return UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: r, style: .continuous)
    case .left:   return UnevenRoundedRectangle(bottomTrailingRadius: r, topTrailingRadius: r, style: .continuous)
    case .top:    return UnevenRoundedRectangle(bottomLeadingRadius: r, bottomTrailingRadius: r, style: .continuous)
    case .bottom: return UnevenRoundedRectangle(topLeadingRadius: r, topTrailingRadius: r, style: .continuous)
    }
}

/// The "classic" DragThing-style tab: a trapezoid that is full width along the
/// screen edge and narrows with angled shoulders toward the inward (protruding)
/// side — the file-folder tab silhouette. SwiftUI coordinate space has its
/// origin at the top-left (y grows downward).
struct ClassicTabShape: InsettableShape {
    let edge: Edge
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        // The shoulder depth scales with the tab's thickness (its short side),
        // capped so it never eats more than a third of the length.
        let thickness = edge.isVertical ? r.width : r.height
        let length = edge.isVertical ? r.height : r.width
        let slant = min(thickness * 0.45, length * 0.3)

        var p = Path()
        switch edge {
        case .top:        // edge = top (full width), inward = bottom (narrowed)
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - slant, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX + slant, y: r.maxY))
        case .bottom:     // edge = bottom (full width), inward = top (narrowed)
            p.move(to: CGPoint(x: r.minX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.maxX - slant, y: r.minY))
            p.addLine(to: CGPoint(x: r.minX + slant, y: r.minY))
        case .left:       // edge = left (full height), inward = right (narrowed)
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - slant))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + slant))
        case .right:      // edge = right (full height), inward = left (narrowed)
            p.move(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY - slant))
            p.addLine(to: CGPoint(x: r.minX, y: r.minY + slant))
        }
        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}
