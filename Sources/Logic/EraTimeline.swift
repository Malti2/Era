import Foundation

// "Eras": Songs nach ihrem Era-/Projekt-Feld gruppiert und zeitlich geordnet (aelteste Era zuerst).
// Jede Era kennt Jahresspanne, Laufzeit und Status-Mix, damit die Liste auf einen Blick zeigt,
// wie viel davon unveroeffentlicht ist. Reine Foundation-Logik.

struct EraSong: Equatable {
    var id: UUID
    var era: String
    var year: Int?
    var duration: Double
    var statuses: [String]

    init(id: UUID = UUID(), era: String, year: Int? = nil, duration: Double = 0, statuses: [String] = []) {
        self.id = id
        self.era = era
        self.year = year
        self.duration = duration
        self.statuses = statuses
    }
}

struct EraGroup: Equatable, Identifiable {
    var id: String { SongSearch.fold(name) }
    /// Leer = Songs ohne Era; die UI setzt dafuer ihren eigenen Text ein.
    var name: String
    var ids: [UUID]
    var years: ClosedRange<Int>?
    var duration: Double
    /// Haeufigster Status zuerst; nur Status, die mindestens ein Song der Era hat.
    var statusCounts: [(name: String, count: Int)]

    static func == (lhs: EraGroup, rhs: EraGroup) -> Bool {
        lhs.name == rhs.name && lhs.ids == rhs.ids && lhs.years == rhs.years && lhs.duration == rhs.duration
            && lhs.statusCounts.map(\.name) == rhs.statusCounts.map(\.name)
            && lhs.statusCounts.map(\.count) == rhs.statusCounts.map(\.count)
    }

    /// "2018" bzw. "2018–2020"; nil ohne Jahresangaben.
    var yearText: String? {
        guard let years else { return nil }
        return years.lowerBound == years.upperBound ? "\(years.lowerBound)" : "\(years.lowerBound)–\(years.upperBound)"
    }
}

enum EraTimeline {
    /// Chronologisch nach fruehestem Jahr (ohne Jahr danach, dann alphabetisch); "ohne Era" zuletzt.
    /// Gleiche Namen mit anderer Schreibweise oder Akzenten landen in einer Gruppe.
    static func groups(of songs: [EraSong]) -> [EraGroup] {
        var order: [String] = []
        var buckets: [String: [EraSong]] = [:]
        var names: [String: String] = [:]
        for song in songs {
            let display = song.era.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = SongSearch.fold(display)
            if buckets[key] == nil { order.append(key); names[key] = display }
            buckets[key, default: []].append(song)
        }
        let result: [EraGroup] = order.map { key in
            let members = buckets[key] ?? []
            let years = members.compactMap(\.year)
            var counts: [String: (name: String, n: Int)] = [:]
            for song in members {
                for status in Set(song.statuses) {
                    let folded = SongSearch.fold(status)
                    counts[folded] = (counts[folded]?.name ?? status, (counts[folded]?.n ?? 0) + 1)
                }
            }
            let statuses = counts.values
                .sorted { $0.n != $1.n ? $0.n > $1.n : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .map { (name: $0.name, count: $0.n) }
            return EraGroup(
                name: names[key] ?? "", ids: members.map(\.id),
                years: years.min().flatMap { low in years.max().map { low...$0 } },
                duration: members.reduce(0) { $0 + $1.duration }, statusCounts: statuses)
        }
        return result.sorted { a, b in
            if a.name.isEmpty != b.name.isEmpty { return b.name.isEmpty }
            switch (a.years?.lowerBound, b.years?.lowerBound) {
            case let (x?, y?) where x != y: return x < y
            case (.some, .none): return true
            case (.none, .some): return false
            default: return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
    }

    /// Lohnt sich eine Era-Ansicht? Erst wenn mindestens ein Song eine Era hat.
    static func isUseful(_ songs: [EraSong]) -> Bool {
        songs.contains { !$0.era.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
