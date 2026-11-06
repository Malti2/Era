import Foundation

// Wochenrueckblick fuer Home: die letzten 7 Tage (inkl. heute) im Vergleich zu den 7 Tagen davor.
struct WeeklyRecap: Equatable {
    struct Day: Equatable, Identifiable {
        var date: Date
        var seconds: Double
        var plays: Int
        var id: Date { date }
    }

    enum Trend: Equatable {
        /// Vorwoche ohne Wiedergaben - kein sinnvoller Prozentwert
        case firstWeek
        case same
        case up(percent: Int)
        case down(percent: Int)
    }

    /// Aelteste zuerst, immer 7 Eintraege (leere Tage mit 0).
    var days: [Day] = []
    var seconds = 0.0
    var plays = 0
    var previousSeconds = 0.0
    var previousPlays = 0
    var topTrack: StatsCalculator.TrackCount?
    var streak = 0

    var hasActivity: Bool { plays > 0 }
    var maxDaySeconds: Double { days.map(\.seconds).max() ?? 0 }

    var trend: Trend {
        guard previousSeconds > 0 else { return .firstWeek }
        let change = (seconds - previousSeconds) / previousSeconds * 100
        let rounded = Int(change.rounded())
        if rounded == 0 { return .same }
        return rounded > 0 ? .up(percent: rounded) : .down(percent: -rounded)
    }

    /// Relative Hoehe eines Tagesbalkens (0...1).
    func barHeight(for day: Day) -> Double {
        maxDaySeconds > 0 ? day.seconds / maxDaySeconds : 0
    }

    static func make(from records: [PlayRecord], now: Date = Date(), calendar: Calendar = .current) -> WeeklyRecap {
        var recap = WeeklyRecap()
        let today = calendar.startOfDay(for: now)
        guard let weekStart = calendar.date(byAdding: .day, value: -6, to: today),
              let previousStart = calendar.date(byAdding: .day, value: -13, to: today) else { return recap }
        var perDay: [Date: (seconds: Double, plays: Int)] = [:]
        var current: [PlayRecord] = []
        for record in records {
            let day = calendar.startOfDay(for: record.date)
            if day >= weekStart && day <= today {
                current.append(record)
                var entry = perDay[day] ?? (0, 0)
                entry.seconds += record.seconds
                entry.plays += 1
                perDay[day] = entry
                recap.seconds += record.seconds
                recap.plays += 1
            } else if day >= previousStart && day < weekStart {
                recap.previousSeconds += record.seconds
                recap.previousPlays += 1
            }
        }
        recap.days = (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            let entry = perDay[day] ?? (0, 0)
            return Day(date: day, seconds: entry.seconds, plays: entry.plays)
        }
        recap.topTrack = StatsCalculator.topTracks(current, limit: 1).first
        recap.streak = StatsCalculator.currentStreak(records, now: now, calendar: calendar)
        return recap
    }
}
