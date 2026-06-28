import Foundation

/// Coarse recency buckets for grouping a date-ranked list (the Recents tab's list
/// layout) into Today / Yesterday / This Week / Older sections. Pure and calendar-
/// injectable so it's unit-testable.
enum TimeBucket: Int, CaseIterable {
    case today
    case yesterday
    case thisWeek
    case older

    var title: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .thisWeek: return "This Week"
        case .older: return "Older"
        }
    }

    /// The bucket a `date` falls into relative to `now`. "This Week" means earlier
    /// than yesterday but within the last 7 days; anything older is "Older".
    /// Computed by date arithmetic against `now` (not `Calendar.isDateInToday`, which
    /// is relative to the real current date) so it's injectable for tests.
    static func bucket(for date: Date, now: Date, calendar: Calendar = .current) -> TimeBucket {
        let startOfToday = calendar.startOfDay(for: now)
        guard let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday),
              let startOfWeek = calendar.date(byAdding: .day, value: -7, to: startOfToday) else {
            return .older
        }
        if date >= startOfToday { return .today }
        if date >= startOfYesterday { return .yesterday }
        if date >= startOfWeek { return .thisWeek }
        return .older
    }

    /// Groups `items` into ordered `(bucket, items)` sections by each item's date,
    /// preserving the incoming order within a bucket and dropping empty buckets.
    /// Items whose `date(_:)` is `nil` fall into `.older`.
    static func grouped<Item>(_ items: [Item], now: Date, calendar: Calendar = .current,
                              date: (Item) -> Date?) -> [(bucket: TimeBucket, items: [Item])] {
        var bins: [TimeBucket: [Item]] = [:]
        for item in items {
            let b = date(item).map { bucket(for: $0, now: now, calendar: calendar) } ?? .older
            bins[b, default: []].append(item)
        }
        return TimeBucket.allCases.compactMap { bucket in
            guard let group = bins[bucket], !group.isEmpty else { return nil }
            return (bucket, group)
        }
    }
}
