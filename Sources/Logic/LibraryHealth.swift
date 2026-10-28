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

    var missingAudio: [MissingAudio] = []
    var emptySongIDs: [UUID] = []
    var brokenArtworkVersionIDs: [UUID] = []
    var orphanAudioFiles: [String] = []
    var orphanArtworkFiles: [String] = []
    var orphanBytes = 0
    var duplicates: [DuplicateGroup] = []

    var isHealthy: Bool {
        missingAudio.isEmpty && emptySongIDs.isEmpty && brokenArtworkVersionIDs.isEmpty
            && orphanAudioFiles.isEmpty && orphanArtworkFiles.isEmpty && duplicates.isEmpty
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
        return report
    }
}
