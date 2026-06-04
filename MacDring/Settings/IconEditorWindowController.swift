import AppKit
import SwiftUI

/// Presents the generated-icon editor (`IconEditorView`) for a drawer item in a
/// small modal-style window and reports the chosen `IconStyle` (or `nil` to clear)
/// back to the caller. A fresh window is built each time so it opens clean.
///
/// Like the New Tab / Settings windows, it switches the app to `.regular` while open
/// so the window can take focus, then reverts via the shared activation-policy guard
/// when it closes.
final class IconEditorWindowController: NSObject, NSWindowDelegate {

    private var window: NSWindow?

    /// Shows the editor for `itemName`, seeded with `initial`. `onSave` is called with
    /// the chosen style (or `nil` for "use default") when the user saves; cancelling
    /// just closes the window.
    func show(itemName: String, initial: IconStyle?, onSave: @escaping (IconStyle?) -> Void) {
        window?.close()

        let view = IconEditorView(
            itemName: itemName,
            initial: initial,
            onSave: { [weak self] style in onSave(style); self?.window?.close() },
            onCancel: { [weak self] in self?.window?.close() }
        )
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Customize Icon"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window

        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.window?.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.revertToAccessoryIfNoOrdinaryWindows(excluding: window)
    }
}
