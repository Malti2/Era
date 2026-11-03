import Foundation

// Hoerverlauf eines einzelnen Songs (Detailansicht) - reine Logik ohne SwiftData.
struct SongListening: Equatable {
    let plays: Int
    let totalSeconds: Double
    let firstPlayed: Date?
    let lastPlayed: Date?
    /// Wiedergaben pro Monat, aelteste zuerst, genau `monthCount` Eintraege; der letzte ist der aktuelle Monat.
    let monthlyPlays: [Int]

    var isEmpty: Bool { plays == 0 }
    /// Mittlere Hoerdauer pro Wiedergabe.
    var averageSeconds: Double { plays > 0 ? totalSeconds / Double(plays) : 0 }

    static func make(from events: [PlayRecord], now: Date = Date(), monthCount: Int = 12, calendar: Calendar = .current) -> SongListening {
        let valid = events.filter { $0.date <= now }
        let thisMonth = StatsCalculator.monthStart(now, calendar: calendar)
        var buckets = [Int](repeating: 0, count: max(monthCount, 1))
        for event in valid {
            let month = StatsCalculator.monthStart(event.date, calendar: calendar)
            let diff = calendar.dateComponents([.month], from: month, to: thisMonth).month ?? Int.max
            if diff >= 0 && diff < buckets.count { buckets[buckets.count - 1 - diff] += 1 }
        }
        return SongListening(
            plays: valid.count,
            totalSeconds: valid.reduce(0) { $0 + $1.seconds },
            firstPlayed: valid.map(\.date).min(),
            lastPlayed: valid.map(\.date).max(),
            monthlyPlays: buckets)
    }
}
