import Foundation

// Bibliotheks-Check: gleicht die Datenbank mit den Dateien im App-Container ab und
// findet kaputte Verweise, verwaiste Dateien und doppelte Songs. Reine Logik auf
// Snapshots - Dateisystem und SwiftData liefern nur die Eingaben.

struct HealthVersion: Equatable {
    var id: UUID
    var name: String
    var fileName: String
    var artworkFile: String?
}

struct HealthSong: Equatable {
    var id: UUID
    var title: String
    var artist: String
    var versions: [HealthVersion]
    var album: String = ""
    var trackNumber: Int = 0
    /// 0 = keine Disc-Angabe (zaehlt als Disc 1).
    var discNumber: Int = 0
}

struct LibraryFilesSnapshot: Equatable {
    /// Dateiname -> Groesse in Bytes (Audiodateien im Bibliotheksordner)
    var audio: [String: Int] = [:]
    var artwork: [String: Int] = [:]
}

struct LibraryHealthReport: Equatable {
    struct MissingAudio: Equatable {
        var songID: UUID
        var versionID: UUID
        var title: String
        var versionName: String
    }
    struct DuplicateGroup: Equatable {
        var title: String
        var artist: String
        var songIDs: [UUID]
    }

    /// Album mit doppelten oder fehlenden Track-Nummern ("Track 3 fehlt"); `songIDs` in Album-Reihenfolge.
    /// Nummern gelten je Disc: Track 1 auf Disc 1 und Track 1 auf Disc 2 ist kein Duplikat.
    struct TrackIssue: Equatable {
        /// Probleme einer einzelnen Disc (nur Discs mit Luecken/Doppelten).
        struct DiscIssue: Equatable {
            var disc: Int
            var duplicates: [Int]
            var missing: [Int]
        }
        var album: String
        var songIDs: [UUID]
        /// Vereinigung ueber alle Discs (Kurztext); Details stehen in `discs`.
        var duplicates: [Int]
        var missing: [Int]
        /// Discs, die komplett fehlen ("Disc 2 ohne Disc 1").
        var missingDiscs: [Int] = []
        var discs: [DiscIssue] = []

        /// true, wenn Neunummerieren etwas reparieren kann (Luecken/Doppelte).
        /// Nur fehlende Discs lassen sich so nicht fixen – die Disc selbst fehlt.
        var fixableByRenumbering: Bool {
            !missing.isEmpty || !duplicates.isEmpty || discs.contains { !$0.missing.isEmpty || !$0.duplicates.isEmpty }
        }
    }

    var missingAudio: [MissingAudio] = []
    var emptySongIDs: [UUID] = []
    var brokenArtworkVersionIDs: [UUID] = []
    var orphanAudioFiles: [String] = []
    var orphanArtworkFiles: [String] = []
    var orphanBytes = 0
    var duplicates: [DuplicateGroup] = []
    /// Songs mit gleichem Basis-Titel ("Song", "Song (Demo)"): vermutlich Versionen desselben Songs. Reiner Hinweis, kein Fehler.
    var similar: [DuplicateGroup] = []
    var trackIssues: [TrackIssue] = []

    /// Stabiler Schluessel einer Gruppe, damit "Ignorieren" ueber Starts hinweg haelt.
    static func groupKey(_ ids: [UUID]) -> String { ids.map(\.uuidString).sorted().joined(separator: "+") }

    func visibleSimilar(ignoring ignored: Set<String>) -> [DuplicateGroup] {
        similar.filter { !ignored.contains(Self.groupKey($0.songIDs)) }
    }

    var isHealthy: Bool {
        missingAudio.isEmpty && emptySongIDs.isEmpty && brokenArtworkVersionIDs.isEmpty
            && orphanAudioFiles.isEmpty && orphanArtworkFiles.isEmpty && duplicates.isEmpty && trackIssues.isEmpty
    }
    var orphanCount: Int { orphanAudioFiles.count + orphanArtworkFiles.count }
}

enum LibraryHealth {
    /// Dateien, die nie angefasst werden duerfen (Legacy-Index, versteckte Dateien).
    static func isManagedAudioFile(_ name: String) -> Bool {
        guard !name.hasPrefix(".") else { return false }
        let ext = (name as NSString).pathExtension.lowercased()
        return ["mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac"].contains(ext)
    }

    static func analyze(songs: [HealthSong], files: LibraryFilesSnapshot) -> LibraryHealthReport {
        var report = LibraryHealthReport()
        var referencedAudio = Set<String>()
        var referencedArtwork = Set<String>()
        for song in songs {
            if song.versions.isEmpty { report.emptySongIDs.append(song.id) }
            for version in song.versions {
                referencedAudio.insert(version.fileName)
                if files.audio[version.fileName] == nil {
                    report.missingAudio.append(.init(songID: song.id, versionID: version.id, title: song.title, versionName: version.name))
                }
                if let art = version.artworkFile {
                    referencedArtwork.insert(art)
                    if files.artwork[art] == nil { report.brokenArtworkVersionIDs.append(version.id) }
                }
            }
        }
        report.orphanAudioFiles = files.audio.keys.filter { !referencedAudio.contains($0) && isManagedAudioFile($0) }.sorted()
        report.orphanArtworkFiles = files.artwork.keys.filter { !referencedArtwork.contains($0) && !$0.hasPrefix(".") }.sorted()
        report.orphanBytes = report.orphanAudioFiles.reduce(0) { $0 + (files.audio[$1] ?? 0) }
            + report.orphanArtworkFiles.reduce(0) { $0 + (files.artwork[$1] ?? 0) }

        var groups: [String: [HealthSong]] = [:]
        for song in songs where !song.title.trimmingCharacters(in: .whitespaces).isEmpty {
            groups[SongSearch.fold(song.title) + "\u{1F}" + SongSearch.fold(song.artist), default: []].append(song)
        }
        report.duplicates = groups.values.filter { $0.count > 1 }
            .map { LibraryHealthReport.DuplicateGroup(title: $0[0].title, artist: $0[0].artist, songIDs: $0.map(\.id)) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        let byID = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let candidates = songs.map { TitleCandidate(id: $0.id, title: $0.title, artist: $0.artist) }
        report.similar = TitleMatching.similarGroups(candidates).compactMap { ids in
            // Anzeigename: der kuerzeste Titel ist meist der Basis-Titel
            let members = ids.compactMap { byID[$0] }
            guard let shortest = members.min(by: { $0.title.count < $1.title.count }) else { return nil }
            return LibraryHealthReport.DuplicateGroup(title: shortest.title, artist: shortest.artist, songIDs: ids)
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        report.trackIssues = trackIssues(in: songs)
        return report
    }

    /// Alben mit mindestens zwei nummerierten Songs, bei denen Nummern doppelt vorkommen oder Luecken haben.
    /// Geprueft wird je Disc (0 = keine Angabe, zaehlt als Disc 1); zusaetzlich melden wir Discs,
    /// die komplett fehlen (z.B. nur Disc 2 importiert). Ein Mehr-CD-Album mit Track 1 auf jeder
    /// Disc ist damit kein falscher Fund mehr.
    static func trackIssues(in songs: [HealthSong]) -> [LibraryHealthReport.TrackIssue] {
        var albums: [String: [HealthSong]] = [:]
        var names: [String: String] = [:]
        for song in songs {
            let name = song.album.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let key = SongSearch.fold(name)
            names[key] = names[key] ?? name
            albums[key, default: []].append(song)
        }
        let issues: [LibraryHealthReport.TrackIssue] = albums.compactMap { key, members in
            let numbered = members.filter { $0.trackNumber > 0 }
            guard numbered.count >= 2 else { return nil }
            var byDisc: [Int: [HealthSong]] = [:]
            for song in members {
                byDisc[song.discNumber > 0 ? song.discNumber : 1, default: []].append(song)
            }
            var discIssues: [LibraryHealthReport.TrackIssue.DiscIssue] = []
            for disc in byDisc.keys.sorted() {
                let numbers = byDisc[disc, default: []].map(\.trackNumber)
                guard numbers.filter({ $0 > 0 }).count >= 2 else { continue }
                let duplicates = TrackOrder.duplicates(in: numbers).sorted()
                let missing = TrackOrder.missing(in: numbers)
                guard !duplicates.isEmpty || !missing.isEmpty else { continue }
                discIssues.append(.init(disc: disc, duplicates: duplicates, missing: missing))
            }
            // Fehlende Discs nur bei Alben mit Disc-Angaben (einzelne Disc-2-Songs nerven nicht).
            let presentDiscs = Set(members.compactMap { $0.discNumber > 0 ? $0.discNumber : nil })
            let missingDiscs = presentDiscs.isEmpty ? [] : (1...(presentDiscs.max() ?? 1)).filter { !presentDiscs.contains($0) }
            guard !discIssues.isEmpty || !missingDiscs.isEmpty else { return nil }
            let order = TrackOrder.sorted(members.map { TrackItem(id: $0.id, trackNumber: $0.trackNumber, discNumber: $0.discNumber, title: $0.title) })
            return .init(album: names[key] ?? "", songIDs: order,
                         duplicates: Array(Set(discIssues.flatMap(\.duplicates))).sorted(),
                         missing: Array(Set(discIssues.flatMap(\.missing))).sorted(),
                         missingDiscs: missingDiscs, discs: discIssues)
        }
        return issues.sorted { $0.album.localizedStandardCompare($1.album) == .orderedAscending }
    }
}
