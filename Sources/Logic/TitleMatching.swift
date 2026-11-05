import Foundation

// Erkennt, ob zwei Titel dasselbe Lied meinen: "Sunrise (Demo)", "Sunrise - v2" und "Sunrise_OG" sind
// Versionen von "Sunrise". Rein auf Strings - wird beim Import (Vorschlag + Versionsname) und im Bibliotheks-Check genutzt.

struct ParsedTitle: Equatable {
    /// Titel ohne Versions-Zusatz, Originalschreibweise
    let base: String
    /// Der entfernte Zusatz ("Demo", "v2"), falls es einen gab
    let hint: String?
}

struct TitleCandidate: Equatable {
    var id: UUID
    var title: String
    var artist: String
}

struct TitleSuggestion: Equatable {
    var id: UUID
    /// Vorgeschlagener Versionsname aus dem Zusatz des neuen Titels, z. B. "Demo"
    var versionName: String?
}

enum TitleMatching {
    private static let keywords: Set<String> = [
        "demo", "live", "remix", "acoustic", "instrumental", "remaster", "remastered", "snippet", "leak", "leaked",
        "alt", "alternate", "alternative", "version", "ver", "edit", "mix", "take", "og", "original", "extended",
        "radio", "rough", "preview", "stripped", "session", "unreleased", "cover", "sketch", "draft", "final"
    ]

    private static func isDescriptor(_ text: String) -> Bool {
        let words = text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard !words.isEmpty, words.count <= 5 else { return false }
        return words.contains { word in
            keywords.contains(word) || (word.hasPrefix("v") && word.dropFirst().allSatisfy(\.isNumber) && word.count > 1)
        }
    }

    private static let patterns: [NSRegularExpression] = [
        #"^(.*\S)\s*[\(\[]([^\)\]]+)[\)\]]\s*$"#,
        #"^(.*\S)\s+[-–—]\s+(.+)$"#,
        #"^(.*\S)[\s_]+(v\d+(?:\.\d+)?)$"#,
        #"^(.*\S)_(og|demo|live|snippet|remaster)$"#
    ].compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    /// Trennt einen Versions-Zusatz am Ende ab - bis zu zwei Mal ("Song (Live) - v2").
    static func parse(_ title: String) -> ParsedTitle {
        var base = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var hints: [String] = []
        for _ in 0..<2 {
            var changed = false
            for pattern in patterns {
                let range = NSRange(base.startIndex..., in: base)
                guard let match = pattern.firstMatch(in: base, range: range),
                      let baseRange = Range(match.range(at: 1), in: base),
                      let hintRange = Range(match.range(at: 2), in: base) else { continue }
                let hint = String(base[hintRange]).trimmingCharacters(in: .whitespaces)
                guard isDescriptor(hint) else { continue }
                hints.insert(hint, at: 0)
                base = String(base[baseRange])
                changed = true
                break
            }
            if !changed { break }
        }
        return ParsedTitle(base: base, hint: hints.isEmpty ? nil : hints.joined(separator: " "))
    }

    /// Verglichen wird akzent-/case-unempfindlich und ohne Satzzeichen.
    static func key(_ title: String) -> String {
        SongSearch.fold(parse(title).base)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }

    /// Passender Versionsname zu einem Zusatz; bekannte Namen landen bei den Standard-Vorgaben.
    static func versionName(for hint: String?) -> String? {
        guard let hint, !hint.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let lower = hint.lowercased()
        let words = lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        if let v = words.first(where: { $0.hasPrefix("v") && $0.count > 1 && $0.dropFirst().allSatisfy(\.isNumber) }) {
            return v.uppercased()
        }
        for (needle, name) in [("demo", "Demo"), ("remaster", "Remaster"), ("live", "Live"), ("snippet", "Snippet")] where words.contains(where: { $0.hasPrefix(needle) }) {
            return name
        }
        if words == ["og"] || words == ["original"] { return "OG" }
        return String(hint.trimmingCharacters(in: .whitespaces).prefix(24))
    }

    /// Eigener Versionstitel, wenn eine importierte Datei an einen Song mit anderem Titel gehaengt wird
    /// ("Sunrise (Demo)" an "Sunrise"); gleicher oder leerer Titel braucht keinen Override.
    static func versionTitle(importing title: String, songTitle: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, SongSearch.fold(trimmed) != SongSearch.fold(songTitle) else { return nil }
        return trimmed
    }

    private static func artistsCompatible(_ a: String, _ b: String) -> Bool {
        let x = SongSearch.fold(a), y = SongSearch.fold(b)
        return x.isEmpty || y.isEmpty || x == y
    }

    /// Bester Kandidat fuer eine neue Datei. Gleiche Basis-Titel schlagen reines Enthaltensein;
    /// bekannte, abweichende Kuenstler schliessen einen Treffer aus.
    static func suggest(title: String, artist: String, in candidates: [TitleCandidate]) -> TitleSuggestion? {
        let parsed = parse(title)
        let needle = key(title)
        guard needle.count >= 3 else { return nil }
        var best: (score: Int, candidate: TitleCandidate)?
        for candidate in candidates where artistsCompatible(artist, candidate.artist) {
            let other = key(candidate.title)
            guard !other.isEmpty else { continue }
            var score = 0
            if other == needle {
                score = 100
            } else if needle.count >= 4 && other.count >= 4 && (other.contains(needle) || needle.contains(other)) {
                score = 40
            }
            guard score > 0 else { continue }
            if !artist.isEmpty && SongSearch.fold(artist) == SongSearch.fold(candidate.artist) { score += 10 }
            if score > (best?.score ?? 0) { best = (score, candidate) }
        }
        guard let best else { return nil }
        return TitleSuggestion(id: best.candidate.id, versionName: versionName(for: parsed.hint))
    }

    /// Gruppen von Songs, die ueber den Basis-Titel zusammengehoeren, deren Titel aber nicht identisch sind
    /// (identische Titel meldet der Duplikat-Check). Mindestens zwei Songs, gleicher oder fehlender Kuenstler.
    static func similarGroups(_ songs: [TitleCandidate]) -> [[UUID]] {
        var buckets: [String: [TitleCandidate]] = [:]
        for song in songs {
            let key = key(song.title)
            guard key.count >= 3 else { continue }
            buckets[key, default: []].append(song)
        }
        var groups: [[UUID]] = []
        for (_, bucket) in buckets where bucket.count > 1 {
            // nach Kuenstler aufteilen; Songs ohne Kuenstler haengen sich an die erste Gruppe
            var byArtist: [String: [TitleCandidate]] = [:]
            var noArtist: [TitleCandidate] = []
            for song in bucket {
                let artist = SongSearch.fold(song.artist)
                if artist.isEmpty { noArtist.append(song) } else { byArtist[artist, default: []].append(song) }
            }
            var clusters = byArtist.keys.sorted().map { byArtist[$0, default: []] }
            if clusters.isEmpty {
                clusters = [noArtist]
            } else if !noArtist.isEmpty, let largest = clusters.indices.max(by: { clusters[$0].count < clusters[$1].count }) {
                clusters[largest] += noArtist
            }
            for cluster in clusters where cluster.count > 1 {
                let titles = Set(cluster.map { SongSearch.fold($0.title) })
                if titles.count > 1 { groups.append(cluster.map(\.id)) }
            }
        }
        return groups.sorted { ($0.first?.uuidString ?? "") < ($1.first?.uuidString ?? "") }
    }
}
