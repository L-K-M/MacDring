import CoreGraphics

/// Deterministic drawer sizing. Computing the drawer's size from the item count
/// and appearance settings (rather than relying on SwiftUI's `fittingSize`, which
/// is ambiguous for a `ScrollView`/`LazyVGrid`) keeps the panel a sensible size
/// and lets `EdgeLayout` position it precisely. Pure and unit-testable.
enum DrawerMetrics {

    static let padding: CGFloat = 28        // 14 on each side
    static let headerHeight: CGFloat = 30
    static let gridSpacing: CGFloat = 12
    static let gridInterColumn: CGFloat = 10

    /// Size for a notes drawer, derived from the tab's grid dimensions (so the
    /// Columns/Rows steppers also size the text area), clamped to the screen.
    static func notesSize(columns: Int, rows: Int, iconSize: CGFloat, in visibleFrame: CGRect) -> CGSize {
        let width = padding + CGFloat(max(1, columns)) * (iconSize + 28)
        let height = padding + headerHeight + CGFloat(max(1, rows)) * (iconSize + 26)
        return CGSize(width: min(max(width, 260), visibleFrame.width - 16),
                      height: min(max(height, 180), visibleFrame.height - 16))
    }

    /// Number of grid rows to show: the tab's configured row count (its height),
    /// grown if needed so items/slots placed beyond it stay visible. The empty
    /// cells within are the droppable gaps for free arrangement.
    static func gridRowCount(configuredRows: Int, maxSlot: Int, itemCount: Int, columns: Int) -> Int {
        let cols = max(1, columns)
        let slotRows = maxSlot >= 0 ? (maxSlot / cols) + 1 : 0
        let itemRows = itemCount > 0 ? ((itemCount - 1) / cols) + 1 : 0
        return max(configuredRows, slotRows, itemRows, 1)
    }

    /// The content size for a drawer, clamped to fit on `visibleFrame`. For the
    /// grid, height is driven by the (configured, possibly grown) row count.
    static func contentSize(itemCount: Int,
                            maxSlot: Int,
                            configuredRows: Int,
                            layout: DrawerLayout,
                            iconSize: CGFloat,
                            columns: Int,
                            in visibleFrame: CGRect) -> CGSize {
        let size: CGSize
        switch layout {
        case .grid:
            let cols = max(1, columns)
            let rows = gridRowCount(configuredRows: configuredRows, maxSlot: maxSlot, itemCount: itemCount, columns: cols)
            let cellWidth = iconSize + 28
            let cellHeight = iconSize + 26
            let width = padding + CGFloat(cols) * cellWidth + CGFloat(cols - 1) * gridInterColumn
            let height = padding + headerHeight
                + CGFloat(rows) * cellHeight + CGFloat(max(rows - 1, 0)) * gridSpacing
            size = CGSize(width: width, height: height)
        case .list:
            let count = max(itemCount, 1)
            let rowHeight = max(iconSize, 22) + 12
            // Width tracks the icon size (plus room for a label) instead of a fixed
            // 300 pt, so large icons / long names aren't cramped. Clamped below.
            let width = max(300, padding + iconSize + 220)
            let height = padding + headerHeight + CGFloat(count) * rowHeight
            size = CGSize(width: width, height: height)
        }
        return CGSize(width: min(size.width, visibleFrame.width - 16),
                      height: min(size.height, visibleFrame.height - 16))
    }
}
