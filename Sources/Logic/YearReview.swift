import Foundation

// Jahresrueckblick aus der lokalen Hoerhistorie: reine Logik ohne SwiftData, damit testbar.
struct YearReview: Equatable {
    let year: Int
    let plays: Int
    let seconds: Double
    let activeDays: Int
    let longestStreak: Int
    /// Tracks, deren allererste Wiedergabe in diesem Jahr liegt.
    let newTracks: Int
    let topTracks: [StatsCalculator.TrackCount]
    let topArtists: [StatsCalculator.ArtistCount]
    let busiestMonth: StatsCalculator.MonthBucket?
    let peakHour: Int?
    /// Index wie `StatsCalculator.weekdayDistribution` (0 = erster Wochentag des Kalenders).
    let busiestWeekdayIndex: Int?

    var isEmpty: Bool { plays == 0 }

    /// Jahre mit mindestens einer Wiedergabe, neuestes zuerst.
    static func availableYears(_ records: [PlayRecord], calendar: Calendar = .current) -> [Int] {
        Array(Set(records.map { calendar.component(.year, from: $0.date) })).sorted(by: >)
    }

    static func make(year: Int, from all: [PlayRecord], calendar: Calendar = .current) -> YearReview {
        let inYear = all.filter { calendar.component(.year, from: $0.date) == year }

        // Erste Wiedergabe je Track ueber die gesamte Historie.
        var firstYear: [String: Int] = [:]
        for record in all.sorted(by: { $0.date < $1.date }) {
            let key = record.title + "\u{1F}" + record.artist
            if firstYear[key] == nil { firstYear[key] = calendar.component(.year, from: record.date) }
        }
        let newTracks = firstYear.values.filter { $0 == year }.count

        let weekdays = StatsCalculator.weekdayDistribution(inYear, calendar: calendar)
        let busiestWeekday: Int? = {
            guard let best = weekdays.max(), best > 0 else { return nil }
            return weekdays.firstIndex(of: best)
        }()
        let busiestMonth = StatsCalculator.monthBuckets(inYear, calendar: calendar)
            .max { lhs, rhs in lhs.plays != rhs.plays ? lhs.plays < rhs.plays : lhs.month > rhs.month }

        return YearReview(
            year: year,
            plays: inYear.count,
            seconds: inYear.reduce(0) { $0 + $1.seconds },
            activeDays: StatsCalculator.activeDays(inYear, calendar: calendar),
            longestStreak: longestStreak(inYear, calendar: calendar),
            newTracks: newTracks,
            topTracks: StatsCalculator.topTracks(inYear, limit: 5),
            topArtists: StatsCalculator.topArtists(inYear, limit: 5),
            busiestMonth: busiestMonth,
            peakHour: StatsCalculator.peakHour(inYear, calendar: calendar),
            busiestWeekdayIndex: busiestWeekday)
    }

    /// Laengste Folge aufeinanderfolgender Tage mit mindestens einer Wiedergabe.
    static func longestStreak(_ records: [PlayRecord], calendar: Calendar = .current) -> Int {
        let days = Set(records.map { calendar.startOfDay(for: $0.date) }).sorted()
        guard var previous = days.first else { return 0 }
        var longest = 1, run = 1
        for day in days.dropFirst() {
            if calendar.date(byAdding: .day, value: 1, to: previous) == day { run += 1 } else { run = 1 }
            longest = max(longest, run)
            previous = day
        }
        return longest
    }
}
