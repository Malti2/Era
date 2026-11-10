import Foundation

// Track-Nummern und Reihenfolge innerhalb eines Albums. 0 = keine Nummer.
// Reine Foundation-Logik (Parsing von Tags, Sortierung, Neu-Nummerierung nach Umsortieren).

enum TrackNumber {
    /// Obergrenze, damit kaputte Tags ("99999") nicht die Anzeige sprengen.
    static let maximum = 999

    /// "3", "03", "3/12", " 7 of 10", "Track 4" -> erste Zahl; sonst 0.
    static func parse(_ raw: String?) -> Int {
        guard let raw else { return 0 }
        var digits = ""
        for character in raw {
            if character.isASCII, character.isNumber { digits.append(character) } else if !digits.isEmpty { break }
        }
        guard let value = Int(digits), value > 0 else { return 0 }
        return min(value, maximum)
    }

    /// MP4-"trkn"-Atom: 2 Byte reserviert, 2 Byte Titel, 2 Byte Gesamtzahl (Big Endian).
    static func fromITunesData(_ bytes: [UInt8]) -> Int {
        guard bytes.count >= 4 else { return 0 }
        let value = Int(bytes[2]) << 8 | Int(bytes[3])
        return value > 0 ? min(value, maximum) : 0
    }

    /// Eingabefeld: leer/ungueltig = keine Nummer.
    static func clamp(_ value: Int) -> Int { min(maximum, max(0, value)) }
}

struct TrackItem: Equatable {
    var id: UUID
    var trackNumber: Int
    var title: String
    var dateAdded: Date

    init(id: UUID = UUID(), trackNumber: Int = 0, title: String = "", dateAdded: Date = Date(timeIntervalSince1970: 0)) {
        self.id = id
        self.trackNumber = trackNumber
        self.title = title
        self.dateAdded = dateAdded
    }
}

enum TrackOrder {
    /// Nummerierte Songs aufsteigend, danach die ohne Nummer in Import-Reihenfolge (Titel als Tiebreaker).
    static func sorted(_ items: [TrackItem]) -> [UUID] {
        items.enumerated().sorted { a, b in
            let (x, y) = (a.element, b.element)
            switch (x.trackNumber > 0, y.trackNumber > 0) {
            case (true, false): return true
            case (false, true): return false
            case (true, true) where x.trackNumber != y.trackNumber: return x.trackNumber < y.trackNumber
            case (false, false) where x.dateAdded != y.dateAdded: return x.dateAdded < y.dateAdded
            default:
                let order = x.title.localizedStandardCompare(y.title)
                return order != .orderedSame ? order == .orderedAscending : a.offset < b.offset
            }
        }.map(\.element.id)
    }

    /// Fortlaufende Nummern 1...n in der gegebenen Reihenfolge; nur Aenderungen kommen zurueck.
    static func renumbered(order: [UUID], current: [UUID: Int]) -> [UUID: Int] {
        var changes: [UUID: Int] = [:]
        for (index, id) in order.enumerated() where current[id] != index + 1 { changes[id] = index + 1 }
        return changes
    }

    /// Naechste freie Nummer hinter der hoechsten vorhandenen.
    static func nextNumber(after existing: [Int]) -> Int { min(TrackNumber.maximum, (existing.max() ?? 0) + 1) }

    /// Nummern, die mehrfach vergeben sind (Hinweis im Editor).
    static func duplicates(in numbers: [Int]) -> Set<Int> {
        var seen = Set<Int>(), result = Set<Int>()
        for number in numbers where number > 0 { if !seen.insert(number).inserted { result.insert(number) } }
        return result
    }

    /// Nummern zwischen 1 und der hoechsten, die niemand hat ("Track 3 fehlt").
    static func missing(in numbers: [Int]) -> [Int] {
        let present = Set(numbers.filter { $0 > 0 })
        guard let top = present.max() else { return [] }
        return (1...top).filter { !present.contains($0) }
    }
}
