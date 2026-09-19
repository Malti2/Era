import SwiftUI
import SwiftData

@main
struct EraApp: App {
    let container = Persistence.shared
    @State private var store: EraStore

    init() {
        let context = ModelContext(container)
        let store = EraStore(context: context)
        _store = State(initialValue: store)
        PlayerEngine.shared.store = store
        store.ensureStatusTags()
        LegacyMigration.migrateIfNeeded(store: store)
        DemoSeed.seedIfNeeded(store: store)
        store.suggestPacksFromLibrary()
        if AppSettings.bool(AppSettings.spotlightEnabledKey),
           let songs = try? store.allSongs(), !songs.isEmpty {
            SpotlightIndexer.reindex(songs: songs)
        }
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--era-import-test") {
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ImportTest", isDirectory: true)
            if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                let sorted = files.sorted { $0.lastPathComponent < $1.lastPathComponent }
                Task {
                    let report = await ImportManager.shared.importFilesForTest(sorted, into: store)
                    let out = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("import-report.txt")
                    try? report.write(to: out, atomically: true, encoding: .utf8)
                }
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(PlayerEngine.shared)
                .environmentObject(ImportManager.shared)
        }
        .modelContainer(container)
    }
}

// Uebernahme der v3.1-Bibliothek (library.json) in das SwiftData-Modell.
enum LegacyMigration {
    private struct LegacySong: Codable {
        let id: UUID
        var title: String
        var artist: String
        var album: String
        var fileName: String
        var duration: Double
        var playCount: Int
        var isFavorite: Bool
    }

    @MainActor
    static func migrateIfNeeded(store: EraStore) {
        let index = LibraryFiles.root.appendingPathComponent("library.json")
        guard let data = try? Data(contentsOf: index),
              let legacy = try? JSONDecoder().decode([LegacySong].self, from: data),
              !legacy.isEmpty,
              (try? store.allSongs().isEmpty) ?? true else { return }
        for old in legacy {
            let song = Song(title: old.title, artist: old.artist, album: old.album)
            song.playCount = old.playCount
            song.isFavorite = old.isFavorite
            let version = SongVersion(name: "OG", fileName: old.fileName, pcmHash: "legacy-\(old.id.uuidString)", duration: old.duration)
            version.song = song
            song.versions.append(version)
            song.primaryVersionID = version.id
            store.insertSong(song)
        }
        store.save()
        try? FileManager.default.moveItem(at: index, to: LibraryFiles.root.appendingPathComponent("library-v3-migriert.json"))
    }
}
