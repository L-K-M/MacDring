import Foundation

/// Moves dropped files into a directory (the Finder-style "file it here" action),
/// renaming to avoid collisions. Used when a file is dropped onto a folder item
/// or a folder tab.
enum FileMover {
    @discardableResult
    static func move(_ urls: [URL], into directory: URL) -> Bool {
        let fileManager = FileManager.default
        var allSucceeded = true
        for url in urls {
            let destination = uniqueDestination(for: url, in: directory, fileManager: fileManager)
            // Don't move a file onto itself (e.g. dropping a folder's own item back in).
            if url.standardizedFileURL == destination.standardizedFileURL { continue }
            do {
                try fileManager.moveItem(at: url, to: destination)
            } catch {
                allSucceeded = false
                NSLog("MacDring: couldn't move \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return allSucceeded
    }

    /// Moves dropped files to the Trash (recoverable — `trashItem`, not a hard
    /// delete). Used when files are dropped onto a Trash item.
    @discardableResult
    static func trash(_ urls: [URL]) -> Bool {
        let fileManager = FileManager.default
        var allSucceeded = true
        for url in urls where url.isFileURL {
            do {
                try fileManager.trashItem(at: url, resultingItemURL: nil)
            } catch {
                allSucceeded = false
                NSLog("MacDring: couldn't trash \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return allSucceeded
    }

    /// A non-colliding destination in `directory` for `url` (appends " 2", " 3", …).
    static func uniqueDestination(for url: URL, in directory: URL, fileManager: FileManager = .default) -> URL {
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var candidate = directory.appendingPathComponent(url.lastPathComponent)
        var counter = 2
        while fileManager.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            candidate = directory.appendingPathComponent(name)
            counter += 1
        }
        return candidate
    }
}
