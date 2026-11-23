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
    struct OnThisDay: Equatable {
        var yearsAgo: Int
        var ids: [UUID]
    }

    /// Songs, die heute vor 1, 2, ... Jahren gehoert wurden (gleicher Monat und Tag).
    /// Das juengste Jahr mit Treffern gewinnt; innerhalb davon die an dem Tag am
    /// haeufigsten gehoerten zuerst, bei Gleichstand die zuletzt gehoerten.
    /// Nur Eintraege mit Song-ID zaehlen (alte Eintraege ohne Song fallen raus).
    static func onThisDay(_ records: [PlayRecord], now: Date = Date(), maxYears: Int = 15,
                          limit: Int = 12, calendar: Calendar = .current) -> OnThisDay? {
        let month = calendar.component(.month, from: now)
        let day = calendar.component(.day, from: now)
        let year = calendar.component(.year, from: now)
        for years in 1...max(1, maxYears) {
            let targetYear = year - years
            var counts: [UUID: (count: Int, latest: Date)] = [:]
            for record in records {
                guard let id = record.songID else { continue }
                let parts = calendar.dateComponents([.year, .month, .day], from: record.date)
                guard parts.year == targetYear, parts.month == month, parts.day == day else { continue }
                let current = counts[id] ?? (0, .distantPast)
                counts[id] = (current.count + 1, max(current.latest, record.date))
            }
            if counts.isEmpty { continue }
            let ids = counts.sorted { lhs, rhs in
                if lhs.value.count != rhs.value.count { return lhs.value.count > rhs.value.count }
                return lhs.value.latest > rhs.value.latest
            }.prefix(limit).map(\.key)
            return OnThisDay(yearsAgo: years, ids: ids)
        }
        return nil
    }

    /// Songs fuer "ab hier nachspielen": ab dem angetippten Eintrag in der Reihenfolge, in der sie gehoert wurden
    /// (aelter -> neuer), ohne Wiederholungen und ohne geloeschte Songs. `entries` ist neueste zuerst.
    static func replayQueue(_ entries: [HistoryEntry], startingAt id: UUID, limit: Int = 100) -> [UUID] {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return [] }
        var seen = Set<UUID>()
        var result: [UUID] = []
        for entry in entries[...index].reversed() {
            guard let songID = entry.songID, seen.insert(songID).inserted else { continue }
            result.append(songID)
            if result.count == limit { break }
        }
        return result
    }

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

enum PlayCounts {
    /// Zaehler nach dem Loeschen von `removed` Wiedergaben; faellt nie unter 0.
    static func afterRemoving(_ removed: Int, from count: Int) -> Int { max(0, count - max(0, removed)) }
}
