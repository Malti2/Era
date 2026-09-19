import Foundation
import AVFoundation
import UniformTypeIdentifiers
import SwiftUI

struct StagedImport: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let name: String
    var title: String
    var artist: String
    var album: String
    var year: Int?
    var suggestedSongID: UUID?
    var linkToSongID: UUID?
    var statusName: String?
    var tagNames: [String] = []
    var versionName: String = "OG"
    var error: String?
}

@MainActor
final class ImportManager: ObservableObject {
    static let shared = ImportManager()

    @Published var isImporting = false
    @Published var message: String?
    @Published var staged: [StagedImport] = []
    @Published var showMassImport = false

    // Security-scoped URLs (folder picks use asCopy: false). Access stays open
    // from staging until the import is confirmed or cancelled, because the
    // staged files live inside the picked folder.
    private var heldScopes: [URL] = []

    private func holdScopes(for urls: [URL]) {
        for url in urls where url.startAccessingSecurityScopedResource() {
            heldScopes.append(url)
        }
    }

    func releaseScopes() {
        for url in heldScopes { url.stopAccessingSecurityScopedResource() }
        heldScopes.removeAll()
    }

    func cancelStaging() {
        staged = []
        releaseScopes()
    }

    static let supportedExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac"]

    static var importableTypes: [UTType] {
        var types: [UTType] = [.audio, .mp3, .mpeg4Audio, .wav, .aiff, .appleProtectedMPEG4Audio]
        for raw in ["public.flac-audio", "org.xiph.flac", "com.apple.coreaudio-format", "public.aifc-audio"] {
            if let t = UTType(raw) { types.append(t) }
        }
        return types
    }

    // MARK: - Direkt-Import (einzeln/mehrere, Ordner-Inhalt)

    func importFiles(_ urls: [URL], into store: EraStore, linkTo song: Song? = nil, versionName: String = "OG") async {
        releaseScopes()
        holdScopes(for: urls)
        defer { releaseScopes() }
        let targets = expandFolders(urls)
        isImporting = true
        var imported = 0, dupes = 0
        var errors: [(String, String)] = []
        for source in targets {
            let name = source.lastPathComponent
            let ext = source.pathExtension.lowercased()
            guard Self.supportedExtensions.contains(ext) else {
                errors.append((name, String(localized: "Unsupported format")))
                continue
            }
            do {
                let data = try Data(contentsOf: source)
                let outcome = try await storeOne(data: data, ext: ext, name: name, into: store, linkTo: song, versionName: versionName)
                switch outcome {
                case .imported: imported += 1
                case .duplicate: dupes += 1
                }
            } catch {
                errors.append((name, error.localizedDescription))
            }
        }
        isImporting = false
        store.suggestPacksFromLibrary()
        if imported > 0, let songs = try? store.allSongs() {
            SpotlightIndexer.reindex(songs: songs)
        }
        message = summary(imported: imported, dupes: dupes, errors: errors)
    }

    enum StoreOutcome { case imported, duplicate }

    @discardableResult
    func storeOne(data: Data, ext: String, name: String, into store: EraStore, linkTo song: Song?, versionName: String, year: Int? = nil, statusName: String? = nil, tagNames: [String] = []) async throws -> StoreOutcome {
        // Hash vor dem Kopieren (Spec 13.2)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
        try data.write(to: tmp, options: .atomic)
        defer { try? FileManager.default.removeItem(at: tmp) }
        guard let hashed = await AudioHasher.hash(url: tmp) else {
            throw NSError(domain: "EraImport", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Audio file could not be read")])
        }
        if let existing = try store.version(matchingHash: hashed.hash, duration: hashed.duration) {
            _ = existing
            return .duplicate // Dupe-Fall: Hinweis statt zweiter Version (Spec 4)
        }
        let meta = await MetadataService.read(url: tmp)
        let versionID = UUID()
        let fileName = "\(versionID.uuidString).\(ext)"
        try data.write(to: LibraryFiles.root.appendingPathComponent(fileName), options: .atomic)

        var artworkFile: String?
        if let art = meta.artworkData {
            let artName = "\(versionID.uuidString).img"
            try? art.write(to: LibraryFiles.artworkURL(artName), options: .atomic)
            artworkFile = artName
        }

        let version = SongVersion(name: versionName, fileName: fileName, pcmHash: hashed.hash, duration: hashed.duration, year: year ?? meta.year)
        version.id = versionID
        version.artworkFile = artworkFile

        let target: Song
        if let song {
            target = song
        } else {
            target = Song(
                title: meta.title?.isEmpty == false ? meta.title! : fallbackTitle(from: name),
                artist: meta.artist ?? "",
                album: meta.album ?? "",
                era: meta.era ?? "",
                year: meta.year
            )
            target.versions.append(version)
            version.song = target
            target.primaryVersionID = version.id
            store.insertSong(target)
        }
        if song != nil {
            version.sortIndex = (target.versions.map(\.sortIndex).max() ?? -1) + 1
            target.versions.append(version)
            version.song = target
        }
        if let statusName, let status = try? store.tag(named: statusName) {
            if !target.tags.contains(where: { $0.id == status.id }) { target.tags.append(status) }
        }
        for tagName in tagNames {
            let tag = store.makeTag(named: tagName)
            if !target.tags.contains(where: { $0.id == tag.id }) { target.tags.append(tag) }
        }
        store.save()
        return .imported
    }

    // MARK: - Massenimport (Staging + Vorschlaege, ein Durchgang - Spec 4)

    func stage(_ urls: [URL], existing songs: [Song]) async {
        releaseScopes()
        holdScopes(for: urls)
        let targets = expandFolders(urls)
        var items: [StagedImport] = []
        for source in targets {
            let name = source.lastPathComponent
            let ext = source.pathExtension.lowercased()
            guard Self.supportedExtensions.contains(ext) else {
                var item = StagedImport(sourceURL: source, name: name, title: name, artist: "", album: "")
                item.error = String(localized: "Unsupported format")
                items.append(item)
                continue
            }
            var item = StagedImport(sourceURL: source, name: name, title: fallbackTitle(from: name), artist: "", album: "")
            if let data = try? Data(contentsOf: source) {
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
                try? data.write(to: tmp)
                let meta = await MetadataService.read(url: tmp)
                if let t = meta.title, !t.isEmpty { item.title = t }
                item.artist = meta.artist ?? ""
                item.album = meta.album ?? ""
                item.year = meta.year
                try? FileManager.default.removeItem(at: tmp)
            }
            item.suggestedSongID = suggestSong(for: item.title, in: songs)?.id
            items.append(item)
        }
        staged = items
        if !items.isEmpty { showMassImport = true }
    }

    // Titel-Aehnlichkeit nur als VORSCHLAG (Spec 11.1): automatisch passiert nichts.
    private func suggestSong(for title: String, in songs: [Song]) -> Song? {
        let needle = title.lowercased()
        guard needle.count >= 3 else { return nil }
        return songs.first { song in
            let t = song.title.lowercased()
            return t == needle || (needle.count >= 4 && (t.contains(needle) || needle.contains(t)))
        }
    }

    func confirmStaged(into store: EraStore, songs: [Song]) async {
        let items = staged
        staged = []
        defer { releaseScopes() }
        isImporting = true
        var imported = 0, dupes = 0
        var errors: [(String, String)] = []
        for item in items where item.error == nil {
            do {
                let data = try Data(contentsOf: item.sourceURL)
                let link = item.linkToSongID.flatMap { id in songs.first { $0.id == id } }
                let outcome = try await storeOne(data: data, ext: item.sourceURL.pathExtension.lowercased(), name: item.name, into: store, linkTo: link, versionName: item.versionName, year: item.year, statusName: item.statusName, tagNames: item.tagNames)
                switch outcome {
                case .imported:
                    imported += 1
                    if let link, let s = link.versions.last?.song {
                        _ = s
                    }
                case .duplicate: dupes += 1
                }
                // Titel/Artist aus der Staging-Liste uebernehmen
                if outcome == .imported {
                    if let all = try? store.allSongs(), let newest = all.first {
                        _ = newest
                    }
                }
            } catch {
                errors.append((item.name, error.localizedDescription))
            }
        }
        isImporting = false
        store.suggestPacksFromLibrary()
        if imported > 0, let songs = try? store.allSongs() {
            SpotlightIndexer.reindex(songs: songs)
        }
        message = summary(imported: imported, dupes: dupes, errors: errors)
    }

    // MARK: - Hilfe

    func expandFolders(_ urls: [URL]) -> [URL] {
        var result: [URL] = []
        var queue = urls
        while let url = queue.popLast() {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                if let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                    queue.append(contentsOf: contents.filter { !$0.lastPathComponent.hasPrefix(".") })
                }
            } else if !url.lastPathComponent.hasPrefix(".") {
                result.append(url)
            }
        }
        return result.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    func fallbackTitle(from fileName: String) -> String {
        URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
    }

    func importFilesForTest(_ urls: [URL], into store: EraStore) async -> String {
        var lines: [String] = []
        for source in expandFolders(urls) {
            let name = source.lastPathComponent
            let ext = source.pathExtension.lowercased()
            guard Self.supportedExtensions.contains(ext) else {
                lines.append("\(name): SKIP Unsupported format")
                continue
            }
            do {
                let data = try Data(contentsOf: source)
                lines.append("\(name): read \(data.count) bytes")
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
                try data.write(to: tmp)
                let hashed = await AudioHasher.hash(url: tmp)
                lines.append("\(name): hash=\(hashed == nil ? "NIL [\(AudioHasher.lastError)]" : "ok") duration=\(hashed?.duration ?? -1)")
                try? FileManager.default.removeItem(at: tmp)
                let outcome = try await storeOne(data: data, ext: ext, name: name, into: store, linkTo: nil, versionName: "OG")
                lines.append("\(name): \(outcome == .imported ? "IMPORTED" : "DUPE")")
            } catch {
                lines.append("\(name): ERROR \(error.localizedDescription)")
            }
        }
        let fileCount = (try? FileManager.default.contentsOfDirectory(atPath: LibraryFiles.root.path))?.count ?? -1
        lines.append("EraLibrary files: \(fileCount)")
        return lines.joined(separator: "\n")
    }

    private func summary(imported: Int, dupes: Int, errors: [(String, String)]) -> String? {
        var parts: [String] = []
        if imported > 0 { parts.append(imported == 1 ? "1 song imported" : "\(imported) songs imported") }
        if dupes > 0 { parts.append(dupes == 1 ? "1 file already in the library" : "\(dupes) files already in the library") }
        if !errors.isEmpty {
            if errors.count == 1 {
                parts.append("\(errors[0].0): \(errors[0].1)")
            } else {
                let reasons = Dictionary(grouping: errors, by: { $0.1 }).map { "\($0.value.count)x \($0.key)" }
                parts.append("\(errors.count) files not imported (\(reasons.joined(separator: ", ")))")
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
