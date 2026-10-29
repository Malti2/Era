import Foundation

// Reine Auswertung der lokalen Hoerhistorie (PlayEvent) - ohne SwiftData, damit testbar.
struct PlayRecord: Equatable {
    let date: Date
    let seconds: Double
    let title: String
    let artist: String
}

enum StatsCalculator {
    struct MonthBucket: Identifiable, Equatable {
        var id: Date { month }
        let month: Date
        var plays: Int
        var seconds: Double
    }

    struct TrackCount: Identifiable, Equatable {
        var id: String { title + "\u{1F}" + artist }
        let title: String
        let artist: String
        let plays: Int
    }

    struct ArtistCount: Identifiable, Equatable {
        var id: String { name }
        let name: String
        let plays: Int
    }

    static func monthStart(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    /// Months with at least one play, newest first.
    static func monthBuckets(_ records: [PlayRecord], calendar: Calendar = .current) -> [MonthBucket] {
        var map: [Date: MonthBucket] = [:]
        for record in records {
            let key = monthStart(record.date, calendar: calendar)
            var bucket = map[key] ?? MonthBucket(month: key, plays: 0, seconds: 0)
            bucket.plays += 1
            bucket.seconds += record.seconds
            map[key] = bucket
        }
        return map.values.sorted { $0.month > $1.month }
    }

    /// The last `months` calendar months including the current one, oldest first, empty months as zero.
    static func monthlySeries(_ records: [PlayRecord], months: Int, now: Date = Date(), calendar: Calendar = .current) -> [MonthBucket] {
        let existing = Dictionary(uniqueKeysWithValues: monthBuckets(records, calendar: calendar).map { ($0.month, $0) })
        let current = monthStart(now, calendar: calendar)
        return (0..<max(months, 0)).reversed().compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: -offset, to: current) else { return nil }
            return existing[month] ?? MonthBucket(month: month, plays: 0, seconds: 0)
        }
    }

    static func records(_ records: [PlayRecord], inMonthOf date: Date, calendar: Calendar = .current) -> [PlayRecord] {
        let start = monthStart(date, calendar: calendar)
        guard let end = calendar.date(byAdding: .month, value: 1, to: start) else { return [] }
        return records.filter { $0.date >= start && $0.date < end }
    }

    static func topTracks(_ records: [PlayRecord], limit: Int) -> [TrackCount] {
        var counts: [String: TrackCount] = [:]
        for record in records {
            let key = record.title + "\u{1F}" + record.artist
            counts[key] = TrackCount(title: record.title, artist: record.artist, plays: (counts[key]?.plays ?? 0) + 1)
        }
        return Array(counts.values.sorted { lhs, rhs in
            if lhs.plays != rhs.plays { return lhs.plays > rhs.plays }
            let byTitle = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            if byTitle != .orderedSame { return byTitle == .orderedAscending }
            return lhs.artist.localizedCaseInsensitiveCompare(rhs.artist) == .orderedAscending
        }.prefix(limit))
    }

    static func topArtists(_ records: [PlayRecord], limit: Int) -> [ArtistCount] {
        var counts: [String: Int] = [:]
        for record in records { counts[record.artist, default: 0] += 1 }
        return Array(counts.map { ArtistCount(name: $0.key, plays: $0.value) }.sorted { lhs, rhs in
            if lhs.plays != rhs.plays { return lhs.plays > rhs.plays }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }.prefix(limit))
    }

    static func activeDays(_ records: [PlayRecord], calendar: Calendar = .current) -> Int {
        Set(records.map { calendar.startOfDay(for: $0.date) }).count
    }

    /// Consecutive days with at least one play. A streak is still alive if the last
    /// play was yesterday, so it does not read as broken before today's first song.
    static func currentStreak(_ records: [PlayRecord], now: Date = Date(), calendar: Calendar = .current) -> Int {
        let days = Set(records.map { calendar.startOfDay(for: $0.date) })
        var day = calendar.startOfDay(for: now)
        if !days.contains(day), let yesterday = calendar.date(byAdding: .day, value: -1, to: day) { day = yesterday }
        var streak = 0
        while days.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }
}
