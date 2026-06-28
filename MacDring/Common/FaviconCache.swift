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
    /// the main actor via `URLSession`'s async API. The locked cache reads/writes are
    /// in synchronous helpers, so no lock is held across the `await`.
    func fetch(for url: URL) async -> NSImage? {
        guard let host = host(of: url) else { return nil }
        switch claim(host) {
        case .cached(let image): return image
        case .skip: return nil
        case .proceed: break
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/favicon.ico"
        guard let faviconURL = components.url,
              let (data, response) = try? await URLSession.shared.data(from: faviconURL),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = NSImage(data: data), image.isValid else { return nil }

        store(image, for: host)
        return image
    }

    private enum Claim { case cached(NSImage); case skip; case proceed }

    /// Synchronously decides whether `fetch` should hit the network, marking the host
    /// as tried so a miss isn't retried.
    private func claim(_ host: String) -> Claim {
        lock.lock(); defer { lock.unlock() }
        if let cached = images[host] { return .cached(cached) }
        if tried.contains(host) { return .skip }
        tried.insert(host)
        return .proceed
    }

    private func store(_ image: NSImage, for host: String) {
        lock.lock(); defer { lock.unlock() }
        images[host] = image
    }
}
