import Foundation
import Combine

/// Owns the persisted `LauncherDocument` and is the single source of truth for
/// tabs and their items. Loads from / saves to JSON in Application Support,
/// atomically and debounced, keeping one `.bak` of the previous good file.
///
/// `document` is `@Published` so SwiftUI settings views update live; `onChange`
/// is a lightweight hook for the (non-SwiftUI) `TabController` to reconcile the
/// on-screen windows after any mutation.
final class TabStore: ObservableObject {

    @Published private(set) var document: LauncherDocument

    /// Called after every mutation (on the main thread).
    var onChange: (() -> Void)?

    /// Whether a document was loaded from disk (vs. a fresh first run). Used to
    /// decide whether to seed a starter tab.
    let loadedFromDisk: Bool

    private let storeURL: URL
    private let bakURL: URL
    private let fileManager: FileManager
    private var saveWorkItem: DispatchWorkItem?

    // MARK: Init

    /// - Parameters:
    ///   - storeURL: where the JSON lives; defaults to Application Support.
    ///   - fileManager: injectable for tests.
    init(storeURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let url = storeURL ?? TabStore.defaultStoreURL(fileManager: fileManager)
        self.storeURL = url
        self.bakURL = url.deletingPathExtension().appendingPathExtension("bak.json")

        // Ensure the containing directory exists so saves succeed even for an
        // injected custom path.
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        if let data = try? Data(contentsOf: url),
           let doc = TabStore.decode(data) {
            self.document = TabStore.normalizingSlots(doc)
            self.loadedFromDisk = true
        } else if let data = try? Data(contentsOf: bakURL),
                  let doc = TabStore.decode(data) {
            // Primary file missing/corrupt — recover from the backup.
            self.document = TabStore.normalizingSlots(doc)
            self.loadedFromDisk = true
        } else {
            self.document = .empty
            self.loadedFromDisk = false
        }
    }

    /// Ensures every item in every tab has a valid, distinct grid slot (migrates
    /// older documents saved before items had slots).
    private static func normalizingSlots(_ document: LauncherDocument) -> LauncherDocument {
        var doc = document
        for i in doc.tabs.indices {
            doc.tabs[i].items = doc.tabs[i].items.assigningMissingSlots()
        }
        return doc
    }

    static func defaultStoreURL(fileManager: FileManager) -> URL {
        let base = (try? fileManager.url(for: .applicationSupportDirectory,
                                         in: .userDomainMask,
                                         appropriateFor: nil,
                                         create: true))
            ?? fileManager.temporaryDirectory
        let dir = base.appendingPathComponent("MacDring", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("launcher.json")
    }

    private static func decode(_ data: Data) -> LauncherDocument? {
        try? JSONDecoder().decode(LauncherDocument.self, from: data)
    }

    // MARK: Reads

    var tabs: [Tab] { document.tabs }

    func tab(id: UUID) -> Tab? { document.tabs.first { $0.id == id } }

    // MARK: Mutations

    func addTab(_ tab: Tab) {
        mutate {
            var tab = tab
            tab.items = tab.items.assigningMissingSlots()
            $0.tabs.append(tab)
        }
    }

    func removeTab(id: UUID) {
        mutate { $0.tabs.removeAll { $0.id == id } }
    }

    /// Replaces a tab (matched by id) with an updated value.
    func updateTab(_ tab: Tab) {
        mutate {
            if let i = $0.tabs.firstIndex(where: { $0.id == tab.id }) {
                $0.tabs[i] = tab
            }
        }
    }

    /// Replaces the entire tab list (e.g. after a reorder in Settings).
    func replaceTabs(_ tabs: [Tab]) {
        mutate { $0.tabs = tabs }
    }

    func addItem(_ item: DrawerItem, toTab tabID: UUID) {
        mutate {
            if let i = $0.tabs.firstIndex(where: { $0.id == tabID }) {
                $0.tabs[i].items.append(item)
                $0.tabs[i].items = $0.tabs[i].items.assigningMissingSlots()   // fill the new item's slot
            }
        }
    }

    func removeItem(id itemID: UUID, fromTab tabID: UUID) {
        mutate {
            if let i = $0.tabs.firstIndex(where: { $0.id == tabID }) {
                $0.tabs[i].items.removeAll { $0.id == itemID }
            }
        }
    }

    func updateItem(_ item: DrawerItem, inTab tabID: UUID) {
        mutate {
            if let i = $0.tabs.firstIndex(where: { $0.id == tabID }),
               let j = $0.tabs[i].items.firstIndex(where: { $0.id == item.id }) {
                $0.tabs[i].items[j] = item
            }
        }
    }

    /// Places an item at a grid `slot`. If another item already occupies that slot
    /// they swap (so the slot the dragged item left becomes the other's); if the
    /// slot is empty the item simply moves there, leaving a gap. This is what makes
    /// free arrangement with gaps possible.
    func placeItem(_ itemID: UUID, atSlot slot: Int, inTab tabID: UUID) {
        mutate {
            guard let ti = $0.tabs.firstIndex(where: { $0.id == tabID }),
                  let ii = $0.tabs[ti].items.firstIndex(where: { $0.id == itemID }) else { return }
            let oldSlot = $0.tabs[ti].items[ii].slot
            guard oldSlot != slot else { return }
            if let occupant = $0.tabs[ti].items.firstIndex(where: { $0.slot == slot }) {
                $0.tabs[ti].items[occupant].slot = oldSlot
            }
            $0.tabs[ti].items[ii].slot = slot
        }
    }

    /// Updates just a tab's anchor (used during drag-to-reposition).
    func setAnchor(_ anchor: ScreenAnchor, forTab tabID: UUID) {
        mutate {
            if let i = $0.tabs.firstIndex(where: { $0.id == tabID }) {
                $0.tabs[i].anchor = anchor
            }
        }
    }

    func setLocked(_ locked: Bool, forTab tabID: UUID) {
        mutate {
            if let i = $0.tabs.firstIndex(where: { $0.id == tabID }) {
                $0.tabs[i].locked = locked
            }
        }
    }

    /// Updates a notes tab's text (edited live in the drawer). Does **not** notify
    /// `onChange`, so editing notes doesn't reconcile/refresh the open drawer and
    /// fight the text editor's cursor.
    func setNotes(_ notes: String, forTab tabID: UUID) {
        mutate(notifyChange: false) {
            if let i = $0.tabs.firstIndex(where: { $0.id == tabID }) {
                $0.tabs[i].notes = notes
            }
        }
    }

    // MARK: Persistence

    private func mutate(notifyChange: Bool = true, _ change: (inout LauncherDocument) -> Void) {
        var doc = document
        change(&doc)
        document = doc
        if notifyChange { onChange?() }
        scheduleSave()
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// Writes immediately (used on quit and in tests). Keeps a `.bak` copy of the
    /// previous good file and writes atomically.
    func saveNow() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(document)
            if fileManager.fileExists(atPath: storeURL.path) {
                try? fileManager.removeItem(at: bakURL)
                try? fileManager.copyItem(at: storeURL, to: bakURL)
            }
            try data.write(to: storeURL, options: .atomic)
        } catch {
            NSLog("MacDring: failed to save launcher document: \(error.localizedDescription)")
        }
    }
}
