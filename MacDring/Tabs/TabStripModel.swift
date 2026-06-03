import AppKit
import Combine

/// Observable visual state for a single tab pill, plus the interaction callbacks
/// the `TabWindowController` wires up. Updating these `@Published` properties
/// re-renders the SwiftUI `TabStripView` in place (no window rebuild).
final class TabStripModel: ObservableObject {
    @Published var title: String
    @Published var colorHex: String
    @Published var glyph: TabGlyph
    @Published var edge: Edge
    /// The drawer for this tab is currently open (drives the pill highlight).
    @Published var isOpen: Bool = false
    /// A file/app is being dragged over the pill (drives the drop highlight).
    @Published var isDropTargeted: Bool = false

    // Interaction callbacks (set by the window controller).
    var onTap: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    var onDropURLs: (([URL]) -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragChanged: (() -> Void)?
    var onDragEnded: (() -> Void)?
    var onRequestSettings: (() -> Void)?
    var onDelete: (() -> Void)?

    init(title: String, colorHex: String, glyph: TabGlyph, edge: Edge) {
        self.title = title
        self.colorHex = colorHex
        self.glyph = glyph
        self.edge = edge
    }
}
