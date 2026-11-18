import Foundation

// M3U-Import: Gegenstueck zum M3U-Export (`PlaylistM3UExport`).
// Liest `#EXTM3U`-Dateien (auch schlichtes M3U ohne EXTINF) und gleicht die
// Eintraege mit der Bibliothek ab – erst per Dateiname, dann per Titel + Kuenstler.

struct M3UEntry: Equatable {
    var title: String
    var artist: String
    var duration: Double
    /// Pfad/Zeile aus der Datei, wie sie dort steht (relativ, absolut oder URL-kodiert).
    var path: String
}

enum PlaylistM3UImport {
    struct LibraryTrack: Equatable {
        var id: UUID
        var title: String
        var artist: String
        /// Dateinamen aller Versionen (ohne Pfad, wie im App-Container abgelegt).
        var fileNames: [String]
    }

    struct MatchResult {
        /// Song-IDs in M3U-Reihenfolge, Dubletten entfernt.
        var matched: [UUID]
        /// Eintraege, zu denen kein Song in der Bibliothek passt.
        var unmatched: [M3UEntry]
    }

    /// Parst M3U/M3U8-Text. `#EXTINF:<sekunden>,Artist - Titel` gehoert zur
    /// naechsten Pfad-Zeile; andere `#`-Zeilen sind Kommentare. Ohne EXTINF
    /// wird der Titel aus dem Dateinamen abgeleitet.
    static func parse(_ text: String) -> [M3UEntry] {
        var entries: [M3UEntry] = []
        var pendingDuration = 0.0
        var pendingLabel: String?
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line == "#EXTM3U" { continue }
            if line.hasPrefix("#EXTINF:") {
                let rest = line.dropFirst("#EXTINF:".count)
                let parts = rest.split(separator: ",", maxSplits: 1)
                pendingDuration = parts.first.flatMap { Double($0) }.map { max(0, $0) } ?? 0
                pendingLabel = parts.count == 2 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : nil
                continue
            }
            if line.hasPrefix("#") { continue }
            let path = line.removingPercentEncoding ?? line
            let (artist, title) = splitLabel(pendingLabel, fallback: fileTitle(path))
            entries.append(M3UEntry(title: title, artist: artist, duration: pendingDuration, path: path))
            pendingDuration = 0
            pendingLabel = nil
        }
        return entries
    }

    /// Gleicht Eintraege mit der Bibliothek ab. Reihenfolge der Versuche je Eintrag:
    /// Dateiname (exakt), Dateiname ohne Endung, Titel + Kuenstler, Titel allein
    /// (nur wenn er in der Bibliothek eindeutig ist).
    static func match(_ entries: [M3UEntry], against library: [LibraryTrack]) -> MatchResult {
        var byFileName: [String: UUID] = [:]
        var byBaseName: [String: UUID] = [:]
        var byTitleArtist: [String: [UUID]] = [:]
        var byTitle: [String: [UUID]] = [:]
        for track in library {
            for name in track.fileNames {
                let key = normalizedFileName(name)
                if byFileName[key] == nil { byFileName[key] = track.id }
                let base = (key as NSString).deletingPathExtension
                if byBaseName[base] == nil { byBaseName[base] = track.id }
            }
            byTitleArtist[titleArtistKey(title: track.title, artist: track.artist), default: []].append(track.id)
            byTitleArtist[titleArtistKey(title: baseTitle(track.title), artist: track.artist), default: []].append(track.id)
            byTitle[normalized(track.title), default: []].append(track.id)
            byTitle[normalized(baseTitle(track.title)), default: []].append(track.id)
        }

        var matched: [UUID] = []
        var seen = Set<UUID>()
        var unmatched: [M3UEntry] = []
        for entry in entries {
            let fileKey = normalizedFileName((entry.path as NSString).lastPathComponent)
            let id: UUID?
            if let hit = byFileName[fileKey] {
                id = hit
            } else if let hit = byBaseName[(fileKey as NSString).deletingPathExtension] {
                id = hit
            } else if let hits = byTitleArtist[titleArtistKey(title: entry.title, artist: entry.artist)], hits.count == 1 {
                id = hits[0]
            } else if let hits = byTitle[normalized(entry.title)], hits.count == 1 {
                id = hits[0]
            } else {
                id = nil
            }
            if let id, seen.insert(id).inserted {
                matched.append(id)
            } else if id == nil {
                unmatched.append(entry)
            }
        }
        return MatchResult(matched: matched, unmatched: unmatched)
    }

    // MARK: - Helfer

    /// "Artist - Titel" aus einem EXTINF-Label; ohne " - " ist alles der Titel.
    /// `fallback` greift, wenn es gar kein Label gibt.
    private static func splitLabel(_ label: String?, fallback: String) -> (artist: String, title: String) {
        guard let label, !label.isEmpty else { return ("", fallback) }
        if let range = label.range(of: " - ") {
            let artist = String(label[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let title = String(label[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            return (artist, title.isEmpty ? fallback : title)
        }
        return ("", label)
    }

    /// Dateiname ohne Pfad und Endung, als Titel-Ersatz.
    private static func fileTitle(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return (name as NSString).deletingPathExtension
    }

    /// "Titel (Demo)" -> "Titel": Klammerzusatz am Ende faellt fuer den Abgleich weg.
    private static func baseTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard let open = trimmed.lastIndex(of: "("), trimmed.hasSuffix(")") else { return trimmed }
        return String(trimmed[..<open]).trimmingCharacters(in: .whitespaces)
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedFileName(_ name: String) -> String {
        normalized((name as NSString).lastPathComponent)
    }

    private static func titleArtistKey(title: String, artist: String) -> String {
        "\(normalized(title))|\(normalized(artist))"
    }
}
