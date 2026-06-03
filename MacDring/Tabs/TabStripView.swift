import SwiftUI
import UniformTypeIdentifiers

/// The colored pill that sits flush against a screen edge. Click toggles the
/// drawer; hovering can open it; dragging repositions it; dropping files adds
/// items. The two corners facing *into* the screen are rounded, so the pill
/// reads as emerging from the edge.
struct TabStripView: View {
    @ObservedObject var model: TabStripModel
    @ObservedObject var preferences: Preferences

    @State private var isDragging = false

    var body: some View {
        let radius = CGFloat(preferences.cornerRadius)
        let shape = pillShape(radius: radius)

        contentStack
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
            .padding(.vertical, model.edge.isVertical ? 9 : 4)
            .padding(.horizontal, model.edge.isVertical ? 4 : 11)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(background(shape: shape))
            .overlay(
                shape.stroke(
                    .white.opacity(model.isDropTargeted ? 0.95 : (model.isOpen ? 0.5 : 0.18)),
                    lineWidth: model.isDropTargeted ? 2 : 1
                )
            )
            .frame(
                width: model.edge.isVertical ? CGFloat(preferences.tabThickness) : nil,
                height: model.edge.isVertical ? nil : CGFloat(preferences.tabThickness)
            )
            .contentShape(Rectangle())
            .onTapGesture { model.onTap?() }
            .onHover { model.onHoverChanged?($0) }
            .gesture(dragGesture)
            .onDrop(of: [UTType.fileURL], isTargeted: dropTargetBinding) { providers in
                handleDrop(providers)
            }
            .help(model.title)
            .contextMenu {
                Button("Configure Tab…") { model.onRequestSettings?() }
                Divider()
                Button("Remove Tab", role: .destructive) { model.onDelete?() }
            }
    }

    // MARK: Content

    @ViewBuilder
    private var contentStack: some View {
        if model.edge.isVertical {
            VStack(spacing: 3) {
                glyphView
                labelView
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
                .font(.system(size: CGFloat(preferences.tabThickness) * 0.42, weight: .semibold))
        case .monogram(let text):
            Text(text.prefix(2))
                .font(.system(size: CGFloat(preferences.tabThickness) * 0.40, weight: .bold))
        }
    }

    @ViewBuilder
    private var labelView: some View {
        if preferences.showTabLabels && !model.title.isEmpty {
            Text(model.title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .fixedSize(horizontal: !model.edge.isVertical, vertical: false)
        }
    }

    // MARK: Background

    private func background(shape: some Shape) -> some View {
        ZStack {
            VisualEffectBlur(material: preferences.drawerMaterial.nsMaterial, blendingMode: .behindWindow)
            Color(hexString: model.colorHex).opacity(model.isOpen ? 0.88 : 0.62)
        }
        .clipShape(shape)
    }

    private func pillShape(radius r: CGFloat) -> UnevenRoundedRectangle {
        switch model.edge {
        case .right:
            return UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: r)
        case .left:
            return UnevenRoundedRectangle(bottomTrailingRadius: r, topTrailingRadius: r)
        case .top:
            return UnevenRoundedRectangle(bottomLeadingRadius: r, bottomTrailingRadius: r)
        case .bottom:
            return UnevenRoundedRectangle(topLeadingRadius: r, topTrailingRadius: r)
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
        loadFileURLs(from: providers) { urls in
            if !urls.isEmpty { model.onDropURLs?(urls) }
        }
        return true
    }
}

/// Loads file URLs from drag-and-drop item providers, calling `completion` on the
/// main thread once all have resolved. Shared by the tab pill and the drawer.
func loadFileURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
    var urls: [URL] = []
    let lock = NSLock()
    let group = DispatchGroup()

    for provider in providers {
        group.enter()
        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
            if let data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                lock.lock()
                urls.append(url)
                lock.unlock()
            }
            group.leave()
        }
    }

    group.notify(queue: .main) { completion(urls) }
}
