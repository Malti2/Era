import Foundation

/// Zeitraum eines Rueckblicks: ein Kalenderjahr oder eine freie Spanne (Start inklusiv, Ende exklusiv).
enum YearReviewRange: Equatable {
    case year(Int)
    case interval(DateInterval)

    /// Aufloesung in konkrete Grenzen; nil nur, wenn der Kalender das Jahr nicht abbilden kann.
    func resolve(calendar: Calendar = .current) -> DateInterval? {
        switch self {
        case .year(let year):
            guard let date = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) else { return nil }
            return calendar.dateInterval(of: .year, for: date)
        case .interval(let interval):
            return interval
        }
    }

    /// Die letzten `months` Kalendermonate inklusive des laufenden, monatsgenau begrenzt.
    static func trailing(months: Int, now: Date = Date(), calendar: Calendar = .current) -> YearReviewRange {
        let current = StatsCalculator.monthStart(now, calendar: calendar)
        guard months > 0,
              let start = calendar.date(byAdding: .month, value: -(months - 1), to: current),
              let end = calendar.date(byAdding: .month, value: 1, to: current) else { return .year(calendar.component(.year, from: now)) }
        return .interval(DateInterval(start: start, end: end))
    }

    /// Von der ersten Wiedergabe bis heute (Tagesgrenzen); ohne Historie das laufende Jahr.
    static func allTime(from records: [PlayRecord], now: Date = Date(), calendar: Calendar = .current) -> YearReviewRange {
        guard let first = records.map(\.date).min() else { return .year(calendar.component(.year, from: now)) }
        let start = calendar.startOfDay(for: first)
        guard let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return .year(calendar.component(.year, from: now)) }
        return .interval(DateInterval(start: start, end: end))
    }

    /// Kurztitel: "2026", "Mar – Aug 2026" oder "Nov 2025 – Feb 2026" (Monat des letzten Tages bei exklusivem Ende).
    func title(calendar: Calendar = .current) -> String {
        switch self {
        case .year(let year):
            return String(year)
        case .interval(let interval):
            let months = calendar.shortMonthSymbols
            let start = calendar.dateComponents([.year, .month], from: interval.start)
            let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
            let end = calendar.dateComponents([.year, .month], from: lastDay)
            guard let sMonth = start.month, let sYear = start.year, let eMonth = end.month, let eYear = end.year,
                  months.indices.contains(sMonth - 1), months.indices.contains(eMonth - 1) else {
                return String(calendar.component(.year, from: interval.start))
            }
            if sYear == eYear, sMonth == eMonth { return "\(months[sMonth - 1]) \(sYear)" }
            if sYear == eYear { return "\(months[sMonth - 1]) – \(months[eMonth - 1]) \(sYear)" }
            return "\(months[sMonth - 1]) \(sYear) – \(months[eMonth - 1]) \(eYear)"
        }
    }
}

// Jahresrueckblick aus der lokalen Hoerhistorie: reine Logik ohne SwiftData, damit testbar.
// `make(year:)` bleibt die Jahres-API; `make(interval:)` wertet freie Zeitraeume aus.
struct YearReview: Equatable {
    let year: Int
    let range: YearReviewRange
    let plays: Int
    let seconds: Double
    let activeDays: Int
    let longestStreak: Int
    /// Tracks, deren allererste Wiedergabe in diesem Zeitraum liegt.
    let newTracks: Int
    let topTracks: [StatsCalculator.TrackCount]
    let topArtists: [StatsCalculator.ArtistCount]
    /// Top-Tracks nach gehoerter Zeit (gleiche Songs, andere Reihenfolge).
    var topTracksByTime: [StatsCalculator.TrackCount] = []
    /// Top-Kuenstler nach gehoerter Zeit (gleiche Songs, andere Reihenfolge).
    var topArtistsByTime: [StatsCalculator.ArtistCount] = []
    /// Hoerzeit/Wiedergaben je Monat der Spanne, aelteste zuerst (max. 24 Monate).
    var monthlySeries: [StatsCalculator.MonthBucket] = []
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
        make(range: .year(year), from: all, calendar: calendar)
    }

    static func make(interval: DateInterval, from all: [PlayRecord], calendar: Calendar = .current) -> YearReview {
        make(range: .interval(interval), from: all, calendar: calendar)
    }

    static func make(range: YearReviewRange, from all: [PlayRecord], calendar: Calendar = .current) -> YearReview {
        let isInRange: (Date) -> Bool = { date in
            switch range {
            case .year(let year): return calendar.component(.year, from: date) == year
            // Halboffen [start, end): DateInterval.contains ist end-inklusiv.
            case .interval(let interval): return date >= interval.start && date < interval.end
            }
        }
        let inRange = all.filter { isInRange($0.date) }
        let year: Int
        switch range {
        case .year(let y): year = y
        case .interval(let interval): year = calendar.component(.year, from: interval.start)
        }

        // Erste Wiedergabe je Track ueber die gesamte Historie.
        var firstPlay: [String: Date] = [:]
        for record in all.sorted(by: { $0.date < $1.date }) {
            let key = record.title + "\u{1F}" + record.artist
            if firstPlay[key] == nil { firstPlay[key] = record.date }
        }
        let newTracks = firstPlay.values.filter(isInRange).count

        let weekdays = StatsCalculator.weekdayDistribution(inRange, calendar: calendar)
        let busiestWeekday: Int? = {
            guard let best = weekdays.max(), best > 0 else { return nil }
            return weekdays.firstIndex(of: best)
        }()
        let busiestMonth = StatsCalculator.monthBuckets(inRange, calendar: calendar)
            .max { lhs, rhs in lhs.plays != rhs.plays ? lhs.plays < rhs.plays : lhs.month > rhs.month }

        return YearReview(
            year: year,
            range: range,
            plays: inRange.count,
            seconds: inRange.reduce(0) { $0 + $1.seconds },
            activeDays: StatsCalculator.activeDays(inRange, calendar: calendar),
            longestStreak: longestStreak(inRange, calendar: calendar),
            newTracks: newTracks,
            topTracks: StatsCalculator.topTracks(inRange, limit: 5),
            topArtists: StatsCalculator.topArtists(inRange, limit: 5),
            topTracksByTime: StatsCalculator.topTracksByTime(inRange, limit: 5),
            topArtistsByTime: StatsCalculator.topArtistsByTime(inRange, limit: 5),
            monthlySeries: monthlySeries(range: range, records: inRange, calendar: calendar),
            busiestMonth: busiestMonth,
            peakHour: StatsCalculator.peakHour(inRange, calendar: calendar),
            busiestWeekdayIndex: busiestWeekday)
    }

    /// Monatsverlauf ueber die gewaehlte Spanne, aelteste zuerst. Lange Spannen
    /// ("All Time") werden auf die letzten 24 Monate begrenzt, damit das Diagramm lesbar bleibt.
    static func monthlySeries(range: YearReviewRange, records: [PlayRecord], calendar: Calendar = .current) -> [StatsCalculator.MonthBucket] {
        guard let interval = range.resolve(calendar: calendar) else { return [] }
        let end = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        let startMonth = StatsCalculator.monthStart(interval.start, calendar: calendar)
        let endMonth = StatsCalculator.monthStart(end, calendar: calendar)
        let span = (calendar.dateComponents([.month], from: startMonth, to: endMonth).month ?? 0) + 1
        return StatsCalculator.monthlySeries(records, months: max(1, min(24, span)), now: end, calendar: calendar)
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
