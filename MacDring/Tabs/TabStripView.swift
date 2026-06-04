import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The colored tab that sits flush against a screen edge. Click toggles the
/// drawer; hovering can open it; dragging repositions it; dropping files adds
/// items. Two looks (`preferences.tabStyle`):
/// - **modern**: a translucent rounded pill, with the two corners facing *into*
///   the screen rounded so it reads as emerging from the edge.
/// - **classic**: a skeuomorphic angled "folder tab" reminiscent of DragThing.
///
/// On the left/right edges the label is printed vertically (a quarter turn) so
/// long names fit along the tab's length and the tab can stay thin.
struct TabStripView: View {
    @ObservedObject var model: TabStripModel
    @ObservedObject var preferences: Preferences

    @State private var isDragging = false

    private var isVertical: Bool { model.edge.isVertical }
    private var isClassic: Bool { preferences.tabStyle == .classic }
    /// The pill's thickness, scaled down for the (more compact) classic style. Must
    /// match `TabWindowController`'s window sizing, which applies the same scale.
    private var thickness: CGFloat { CGFloat(preferences.tabThickness) * preferences.tabStyle.thicknessScale }
    /// Glyph size relative to thickness — a little smaller for classic so its icon
    /// reads as a compact folder-tab marker rather than filling the pill.
    private var glyphScale: CGFloat { isClassic ? 0.36 : 0.42 }

    var body: some View {
        styledTab
            // Modern pins the thin (perpendicular) axis to `thickness`; classic
            // leaves it free so the folder tab hugs its content and stays compact
            // (the window controller sizes to the same fitting size).
            .frame(
                width: (isVertical && !isClassic) ? thickness : nil,
                height: (!isVertical && !isClassic) ? thickness : nil
            )
            .contentShape(Rectangle())
            .onTapGesture { model.onTap?() }
            .onHover { model.onHoverChanged?($0) }
            .gesture(dragGesture)
            .onDrop(of: [UTType.fileURL, UTType.url], isTargeted: dropTargetBinding) { providers in
                handleDrop(providers)
            }
            .help(model.title)
            .contextMenu {
                Button("Configure Tab…") { model.onRequestSettings?() }
                Menu("Move to Edge") {
                    ForEach(Edge.allCases) { edge in
                        Button(edge.displayName) { model.onMoveToEdge?(edge) }
                    }
                }
                Divider()
                Button("Remove Tab", role: .destructive) { model.onDelete?() }
            }
    }

    @ViewBuilder
    private var styledTab: some View {
        switch preferences.tabStyle {
        case .modern:  modernTab
        case .classic: classicTab
        }
    }

    // MARK: Modern pill

    private var modernTab: some View {
        let shape = edgeRoundedRect(edge: model.edge, radius: CGFloat(preferences.cornerRadius))
        return contentStack
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
            .padding(.vertical, isVertical ? 9 : 4)
            .padding(.horizontal, isVertical ? 4 : 11)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                ZStack {
                    VisualEffectBlur(material: preferences.drawerMaterial.nsMaterial, blendingMode: .behindWindow)
                    Color(hexString: model.colorHex).opacity(model.isOpen ? 0.88 : 0.62)
                }
                .clipShape(shape)
            )
            .overlay(
                shape.stroke(
                    .white.opacity(model.isDropTargeted ? 0.95 : (model.isOpen ? 0.5 : 0.18)),
                    lineWidth: model.isDropTargeted ? 2 : 1
                )
            )
    }

    // MARK: Classic folder tab

    private var classicTab: some View {
        let base = Color(hexString: model.colorHex)
        let shape = ClassicTabShape(edge: model.edge)
        return contentStack
            .foregroundStyle(base.readableForeground)
            // Generous padding *along* the edge so the label has clear side
            // breathing room (à la DragThing's folder tabs), and a thin
            // perpendicular padding so the tab hugs the label and stays short.
            .padding(.vertical, isVertical ? 14 : 4)
            .padding(.horizontal, isVertical ? 4 : 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                shape.fill(
                    LinearGradient(
                        colors: [base.opacity(model.isOpen ? 1.0 : 0.95),
                                 base.opacity(model.isOpen ? 0.80 : 0.72)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            )
            .overlay(shape.strokeBorder(.white.opacity(0.4), lineWidth: 1))   // raised bevel
            .overlay(shape.stroke(.black.opacity(0.3), lineWidth: 1))          // outline
            .overlay {
                if model.isDropTargeted { shape.stroke(.white, lineWidth: 2) }
            }
    }

    // MARK: Content (glyph + label)

    @ViewBuilder
    private var contentStack: some View {
        if isVertical {
            VStack(spacing: 5) {
                glyphView
                rotatedLabel
            }
        } else {
            HStack(spacing: 6) {
                glyphView
                labelView
            }
        }
    }

    @ViewBuilder
    private var glyphView: some View {
        switch model.glyph {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: thickness * glyphScale, weight: .semibold))
        case .monogram(let text):
            Text(text.prefix(2))
                .font(.system(size: thickness * (glyphScale - 0.02), weight: .bold))
        }
    }

    /// Horizontal-edge (top/bottom) label: plain text alongside the glyph.
    @ViewBuilder
    private var labelView: some View {
        if preferences.showTabLabels && !model.title.isEmpty {
            Text(model.title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .fixedSize()
        }
    }

    /// Vertical-edge (left/right) label: the name printed along the tab's length
    /// (a quarter turn), so long names fit without widening the tab.
    ///
    /// The footprint is computed *synchronously* from the text metrics (rather than
    /// a GeometryReader/preference round-trip) so the tab window — which measures
    /// `fittingSize` once at placement — sizes to the full label on first render.
    /// `rotationEffect` doesn't change a view's layout bounds, so we transpose the
    /// frame by hand. A small slack avoids truncation if SwiftUI's metrics differ.
    @ViewBuilder
    private var rotatedLabel: some View {
        if preferences.showTabLabels && !model.title.isEmpty {
            let measured = (model.title as NSString)
                .size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium)])
            Text(model.title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .fixedSize()
                .rotationEffect(.degrees(-90))
                .frame(width: ceil(measured.height), height: ceil(measured.width) + 6)
        }
    }

    // MARK: Drag to reposition

    private var dragGesture: some Gesture {
        // The window follows the cursor via the controller, which reads the global
        // mouse location — so we only use the gesture to signal begin/change/end.
        // (Using `value.translation` here would lag, because the gesture's local
        // reference frame moves with the window as it's dragged.)
        DragGesture(minimumDistance: 8)
            .onChanged { _ in
                if !isDragging {
                    isDragging = true
                    model.onDragBegan?()
                }
                model.onDragChanged?()
            }
            .onEnded { _ in
                isDragging = false
                model.onDragEnded?()
            }
    }

    // MARK: Drop

    private var dropTargetBinding: Binding<Bool> {
        Binding(
            get: { model.isDropTargeted },
            set: { targeted in
                model.isDropTargeted = targeted
                model.onDragHover?(targeted)   // spring-load the drawer on drag-hover
            }
        )
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        loadDroppedURLs(from: providers) { urls in
            if !urls.isEmpty { model.onDropURLs?(urls) }
        }
        return true
    }
}

/// Loads dropped URLs — both file URLs and web links — from drag-and-drop item
/// providers, calling `completion` on the main thread once all have resolved.
/// `NSItemProvider`'s `URL` loader reads `public.file-url` and `public.url` alike,
/// so a file dragged from Finder and a link dragged from a browser both arrive.
func loadDroppedURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
    var urls: [URL] = []
    let lock = NSLock()
    let group = DispatchGroup()

    for provider in providers {
        group.enter()
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            if let url {
                lock.lock()
                urls.append(url)
                lock.unlock()
            }
            group.leave()
        }
    }

    group.notify(queue: .main) { completion(urls) }
}
