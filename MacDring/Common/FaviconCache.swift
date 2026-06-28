import AppKit

/// Best-effort favicon cache for web-link (`.url`) items: fetches a host's
/// `https://<host>/favicon.ico` once, keeps it in memory, and hands it back so the
/// drawer can swap the generic globe for the site's own icon. A host with no usable
/// favicon is remembered as "tried" so it isn't refetched on every drawer open. The
/// cache lives for the app session only (no on-disk persistence).
///
/// `@unchecked Sendable`: state is guarded by `lock`, and `NSImage` is effectively
/// immutable once decoded here.
final class FaviconCache: @unchecked Sendable {
    static let shared = FaviconCache()

    private let lock = NSLock()
    private var images: [String: NSImage] = [:]
    private var tried: Set<String> = []

    private func host(of url: URL) -> String? { url.host?.lowercased() }

    /// The cached favicon for `url`'s host, if one has already been fetched — a
    /// synchronous lookup so `ItemView.resolveIcon` can render it immediately.
    func cached(for url: URL) -> NSImage? {
        guard let host = host(of: url) else { return nil }
        lock.lock(); defer { lock.unlock() }
        return images[host]
    }

    /// Fetches the host's favicon if it isn't cached and hasn't already failed.
    /// Returns the image (cached or freshly fetched) or `nil`. Network work runs off
    /// the main actor via `URLSession`'s async API.
    func fetch(for url: URL) async -> NSImage? {
        guard let host = host(of: url) else { return nil }
        lock.lock()
        if let cached = images[host] { lock.unlock(); return cached }
        if tried.contains(host) { lock.unlock(); return nil }
        tried.insert(host)
        lock.unlock()

        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/favicon.ico"
        guard let faviconURL = components.url,
              let (data, response) = try? await URLSession.shared.data(from: faviconURL),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = NSImage(data: data), image.isValid else { return nil }

        lock.lock(); images[host] = image; lock.unlock()
        return image
    }
}
