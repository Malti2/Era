import Foundation

// Reine Statistik-Logik ueber Wiedergabe-Snapshots (keine SwiftData-Abhaengigkeit,
// damit sie sich ohne Store testen laesst).

struct PlayRecord: Hashable {
    var date: Date
    var seconds: Double
    var title: String
    var artist: String

    init(date: Date, seconds: Double, title: String, artist: String) {
        self.date = date
        self.seconds = seconds
        self.title = title
        self.artist = artist
    }

    init(_ event: PlayEvent) {
        self.init(date: event.date, seconds: event.seconds, title: event.title, artist: event.artist)
    }
}

enum StatsRange: String, CaseIterable, Identifiable {
    case week, month, year, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .week: String(localized: "7 Days")
        case .month: String(localized: "30 Days")
        case .year: String(localized: "12 Months")
        case .all: String(localized: "All Time")
        }
    }
}

struct StatsBucket: Identifiable, Equatable {
    var date: Date
    var plays: Int
    var seconds: Double
    var id: Date { date }
}

struct TrackStat: Identifiable, Equatable {
    var title: String
    var artist: String
    var plays: Int
    var seconds: Double
    var id: String { "\(title)\u{1F}\(artist)" }
}

struct ArtistStat: Identifiable, Equatable {
    var name: String
    var plays: Int
    var seconds: Double
    var id: String { name }
}

struct StatsCalculator {
    var calendar: Calendar = .current
    var now: Date = Date()

    /// Start of the window (inclusive); nil means "everything".
    func start(of range: StatsRange) -> Date? {
        let today = calendar.startOfDay(for: now)
        switch range {
        case .week: return calendar.date(byAdding: .day, value: -6, to: today)
        case .month: return calendar.date(byAdding: .day, value: -29, to: today)
        case .year:
            let month = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? today
            return calendar.date(byAdding: .month, value: -11, to: month)
        case .all: return nil
        }
    }

    func records(_ all: [PlayRecord], in range: StatsRange) -> [PlayRecord] {
        guard let start = start(of: range) else { return all }
        return all.filter { $0.date >= start }
    }

    /// Daily buckets for week/month, monthly buckets for year/all. Gaps are zero-filled
    /// so the chart shows quiet days instead of skipping them.
    func buckets(_ all: [PlayRecord], range: StatsRange) -> [StatsBucket] {
        let daily = range == .week || range == .month
        let component: Calendar.Component = daily ? .day : .month
        func key(_ date: Date) -> Date {
            daily ? calendar.startOfDay(for: date)
                  : (calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date)
        }
        let scoped = records(all, in: range)
        var map: [Date: StatsBucket] = [:]
        for record in scoped {
            let k = key(record.date)
            var bucket = map[k] ?? StatsBucket(date: k, plays: 0, seconds: 0)
            bucket.plays += 1
            bucket.seconds += record.seconds
            map[k] = bucket
        }
        guard let first = (start(of: range).map(key) ?? map.keys.min()) else { return [] }
        let last = key(now)
        var result: [StatsBucket] = []
        var cursor = first
        while cursor <= last && result.count < 1200 {
            result.append(map[cursor] ?? StatsBucket(date: cursor, plays: 0, seconds: 0))
            guard let next = calendar.date(byAdding: component, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    func topTracks(_ records: [PlayRecord], limit: Int) -> [TrackStat] {
        var map: [String: TrackStat] = [:]
        for record in records {
            let probe = TrackStat(title: record.title, artist: record.artist, plays: 0, seconds: 0)
            var stat = map[probe.id] ?? probe
            stat.plays += 1
            stat.seconds += record.seconds
            map[probe.id] = stat
        }
        return Array(map.values.sorted { lhs, rhs in
            if lhs.plays != rhs.plays { return lhs.plays > rhs.plays }
            let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            return lhs.artist.localizedCaseInsensitiveCompare(rhs.artist) == .orderedAscending
        }.prefix(limit))
    }

    func topArtists(_ records: [PlayRecord], limit: Int) -> [ArtistStat] {
        var map: [String: ArtistStat] = [:]
        for record in records {
            let name = record.artist
            var stat = map[name] ?? ArtistStat(name: name, plays: 0, seconds: 0)
            stat.plays += 1
            stat.seconds += record.seconds
            map[name] = stat
        }
        return Array(map.values.sorted { lhs, rhs in
            if lhs.plays != rhs.plays { return lhs.plays > rhs.plays }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }.prefix(limit))
    }

    /// Distinct calendar days with at least one play, oldest first.
    func activeDays(_ all: [PlayRecord]) -> [Date] {
        Set(all.map { calendar.startOfDay(for: $0.date) }).sorted()
    }

    /// Consecutive days with plays ending today. A streak stays alive until the
    /// end of today, so "yesterday but not yet today" still counts.
    func currentStreak(_ all: [PlayRecord]) -> Int {
        let days = Set(activeDays(all))
        var cursor = calendar.startOfDay(for: now)
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }
        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    func longestStreak(_ all: [PlayRecord]) -> Int {
        let days = activeDays(all)
        var best = 0, run = 0
        var previous: Date?
        for day in days {
            if let p = previous, calendar.date(byAdding: .day, value: 1, to: p) == day { run += 1 } else { run = 1 }
            best = max(best, run)
            previous = day
        }
        return best
    }

    /// Relative share of the top entry (0...1) for the inline bars.
    static func share(_ value: Int, of maximum: Int) -> Double {
        maximum > 0 ? Double(value) / Double(maximum) : 0
    }

    /// Compact duration like "3 h 20 min" / "45 min" (locale-neutral units).
    static func durationText(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600, minutes = (total % 3600) / 60
        return hours > 0 ? "\(hours) h \(minutes) min" : "\(minutes) min"
    }
}
