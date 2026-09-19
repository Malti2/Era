import Foundation
import SwiftData

// Demo-Daten fuer Simulator-Screenshots (nur Simulator, nur wenn Bibliothek leer).
// Bildet die Spec-Beispiele ab: 530, Hurricane, Runaway, City in the Sky, Everybody.
enum DemoSeed {
    @MainActor
    static func seedIfNeeded(store: EraStore) {
        #if targetEnvironment(simulator)
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--era-demo"), !args.contains("--era-no-seed") else { return }
        guard ((try? store.allSongs().isEmpty) ?? true) else { return }

        store.ensureStatusTags()
        func tag(_ name: String) -> Tag { store.makeTag(named: name) }

        let nocturne = tag("Nocturne"), horizon = tag("Horizon"), archive = tag("Archive"), studio = tag("Studio")
        let favorite = tag("Favorite")
        let released = tag("Released"), unreleased = tag("Unreleased"), leak = tag("Leak"), demo = tag("Demo")

        func song(_ title: String, _ artist: String, _ era: String, _ year: Int?, versions: [(String, Int?)], tags: [Tag], plays: Int) -> Song {
            let s = Song(title: title, artist: artist, album: era, era: era, year: year)
            s.playCount = plays
            if plays > 0 { s.lastPlayedAt = Date().addingTimeInterval(-3600 * Double(plays)) }
            for (i, v) in versions.enumerated() {
                let ver = SongVersion(name: v.0, fileName: "demo-\(s.id.uuidString)-\(i).m4a", pcmHash: "demo-\(s.id.uuidString)-\(i)", duration: Double(150 + i * 37), year: v.1)
                ver.sortIndex = i
                ver.song = s
                s.versions.append(ver)
                if i == 0 { s.primaryVersionID = ver.id }
            }
            s.tags = tags
            store.insertSong(s)
            return s
        }

        let nightDrive = song("Night Drive", "Nova Lane", "Nocturne", 2025, versions: [("OG", 2024), ("Studio Demo", 2025), ("Released", 2025)], tags: [nocturne, unreleased], plays: 12)
        let northernLights = song("Northern Lights", "Atlas North", "Horizon", 2026, versions: [("First Mix", 2024), ("Live Session", 2025), ("Album Version", 2026), ("Demo", 2023)], tags: [horizon, released, favorite], plays: 30)
        let openRoad = song("Open Road", "The Paper Suns", "Open Skies", 2024, versions: [("Released", 2024)], tags: [archive, released, favorite], plays: 44)
        let cityLights = song("City Lights", "Echo Harbor", "After Hours", 2025, versions: [("OG", 2024), ("Acoustic", 2025)], tags: [studio, unreleased], plays: 9)
        let satellites = song("Satellites", "Juniper Vale", "Nocturne", 2025, versions: [("V1", 2024), ("V2", 2025)], tags: [nocturne, leak], plays: 17)
        let playerTitle = "Afterglow Across the City After Midnight"
        let afterglow = song(playerTitle, "Silver Pines", "Daybreak", 2026, versions: [("OG", 2026)], tags: [released, favorite], plays: 5)

        let vPack = Pack(name: "Nocturne", tagIDs: [nocturne.id], confirmed: true)
        store.insertPack(vPack)
        store.insertPack(Pack(name: "Horizon", tagIDs: [horizon.id], confirmed: false))
        store.insertPack(Pack(name: "Studio Archive", tagIDs: [studio.id], confirmed: false))
        store.insertPack(Pack(name: "Unreleased Mixes", statusNames: ["Unreleased"], confirmed: false))

        northernLights.isFavorite = true
        openRoad.isFavorite = true
        afterglow.isFavorite = true
        openRoad.resumePosition = 62

        let favs = Playlist(name: "Studio Favorites")
        favs.filterTagIDs = []
        store.insertPlaylist(favs)
        store.appendEntry(song: openRoad, version: openRoad.primaryVersion, to: favs)
        store.appendEntry(song: cityLights, version: cityLights.primaryVersion, to: favs)
        store.appendEntry(song: satellites, version: satellites.sortedVersions.last, to: favs)
        store.appendEntry(song: nightDrive, version: nightDrive.primaryVersion, to: favs)
        store.appendEntry(song: northernLights, version: northernLights.sortedVersions.first(where: { $0.name == "Album Version" }), to: favs)
        // Listening history so stats/screenshots look real
        let demoSongs = [openRoad, northernLights, satellites, nightDrive, cityLights, afterglow]
        for (index, demoSong) in demoSongs.enumerated() {
            let events = min(demoSong.playCount, 14)
            for i in 0..<events {
                let daysAgo = Double((i * 3 + index) % 45)
                let event = PlayEvent(date: Date().addingTimeInterval(-daysAgo * 86_400 - Double(i) * 3_700),
                                      seconds: demoSong.primaryVersion?.duration ?? 180,
                                      songID: demoSong.id, title: demoSong.title, artist: demoSong.displayArtist)
                store.context.insert(event)
            }
        }
        store.save()
        #endif
    }
}
