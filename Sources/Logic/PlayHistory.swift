import Foundation

// Hoerverlauf als Tagesliste (Verlauf-Bildschirm und Song-Detail) - reine Logik ohne SwiftData.

struct HistoryEntry: Equatable, Identifiable {
    let id: UUID
    let date: Date
    let seconds: Double
    let title: String
    let artist: String
    let songID: UUID?

    init(id: UUID = UUID(), date: Date, seconds: Double, title: String, artist: String = "", songID: UUID? = nil) {
        self.id = id
        self.date = date
        self.seconds = seconds
        self.title = title
        self.artist = artist
        self.songID = songID
    }
}

struct HistoryDay: Equatable, Identifiable {
    /// Tagesbeginn
    let day: Date
    /// Neueste zuerst
    let entries: [HistoryEntry]

    var id: Date { day }
    var plays: Int { entries.count }
    var seconds: Double { entries.reduce(0) { $0 + $1.seconds } }
    /// Verschiedene Songs an diesem Tag (Eintraege ohne Song-ID zaehlen nach Titel/Kuenstler).
    var uniqueSongs: Int {
        Set(entries.map { $0.songID.map { "id:" + $0.uuidString } ?? "t:" + SongSearch.fold($0.title) + "\u{1F}" + SongSearch.fold($0.artist) }).count
    }
}

enum HistoryDayLabel: Equatable {
    case today, yesterday
    case date(Date)
}

enum PlayHistory {
    /// Gruppiert nach Kalendertag, neueste Tage und Eintraege zuerst. Eintraege in der Zukunft
    /// (Uhr verstellt) werden nicht ausgeblendet - sie landen einfach oben.
    static func days(_ entries: [HistoryEntry], calendar: Calendar = .current) -> [HistoryDay] {
        let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in
            HistoryDay(day: day, entries: grouped[day, default: []].sorted { $0.date > $1.date })
        }
    }

    static func label(for day: Date, now: Date = Date(), calendar: Calendar = .current) -> HistoryDayLabel {
        if calendar.isDate(day, inSameDayAs: now) { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) {
            return .yesterday
        }
        return .date(day)
    }

    /// Alle Begriffe muessen in Titel oder Kuenstler vorkommen (akzent-/case-unempfindlich).
    static func filter(_ entries: [HistoryEntry], query: String) -> [HistoryEntry] {
        let terms = SongSearch.fold(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !terms.isEmpty else { return entries }
        return entries.filter { entry in
            let haystack = SongSearch.fold(entry.title) + " " + SongSearch.fold(entry.artist)
            return terms.allSatisfy { haystack.contains($0) }
        }
    }
}

/// Platzierung eines Songs nach Wiedergaben ("Platz 3 von 120").
struct SongRank: Equatable {
    let position: Int
    let total: Int

    /// `higher` = Songs mit mehr Wiedergaben (Gleichstand teilt sich den Platz). Ohne Wiedergaben gibt es keinen Rang.
    static func make(playCount: Int, higher: Int, total: Int) -> SongRank? {
        guard playCount > 0, total > 0, higher >= 0 else { return nil }
        return SongRank(position: min(higher + 1, total), total: total)
    }

    /// Anteil der Songs, die davor liegen, in Prozent (1 = Spitze). Gibt nur fuer die oberen 10 % einen Wert zurueck.
    var topPercent: Int? {
        let percent = Int((Double(position) / Double(total) * 100).rounded(.up))
        return total >= 10 && percent <= 10 ? max(percent, 1) : nil
    }
}
