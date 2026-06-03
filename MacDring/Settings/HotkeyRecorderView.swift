import SwiftUI
import AppKit

/// A small control that records a global hotkey: click it, then press a key
/// combination (which must include a modifier). Used in the Tabs pane to set a
/// tab's optional toggle shortcut.
struct HotkeyRecorderView: View {
    @Binding var hotkey: HotkeySpec?

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggle) {
                Text(label)
                    .frame(minWidth: 130)
            }
            if hotkey != nil && !recording {
                Button("Clear") { hotkey = nil }
            }
        }
        .onDisappear(perform: stop)
    }

    private var label: String {
        if recording { return "Press shortcut… (Esc to cancel)" }
        if let hotkey { return KeyCodes.displayString(for: hotkey) }
        return "Record Shortcut"
    }

    private func toggle() {
        recording ? stop() : start()
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 {            // Escape cancels
                stop()
                return nil
            }
            let modifiers = KeyCodes.carbonModifiers(from: event.modifierFlags)
            if KeyCodes.hasModifier(modifiers) {
                hotkey = HotkeySpec(keyCode: UInt32(event.keyCode), carbonModifiers: modifiers)
                stop()
            }
            return nil                          // consume keys while recording
        }
    }

    private func stop() {
        recording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
