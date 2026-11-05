import Foundation
import SwiftData

// Hoerverlauf verwalten: einzelne Wiedergaben oder den ganzen Verlauf (eines Songs) loeschen.
extension EraStore {
    /// Loescht die genannten Wiedergaben. Gibt die Anzahl tatsaechlich geloeschter Eintraege zurueck.
    @discardableResult
    func deletePlayEvents(ids: [UUID]) -> Int {
        guard !ids.isEmpty else { return 0 }
        let wanted = Set(ids)
        let events = ((try? context.fetch(FetchDescriptor<PlayEvent>())) ?? []).filter { wanted.contains($0.id) }
        removeEvents(events)
        return events.count
    }

    /// Loescht die Wiedergaben und zieht sie von `Song.playCount` ab (nie unter 0), damit Rang,
    /// "Meistgespielt" und "Nicht gespielt" zum bereinigten Verlauf passen.
    private func removeEvents(_ events: [PlayEvent]) {
        guard !events.isEmpty else { return }
        var removedPerSong: [UUID: Int] = [:]
        for event in events {
            if let id = event.songID { removedPerSong[id, default: 0] += 1 }
            context.delete(event)
        }
        if !removedPerSong.isEmpty {
            for song in (try? context.fetch(FetchDescriptor<Song>())) ?? [] {
                guard let removed = removedPerSong[song.id] else { continue }
                song.playCount = PlayCounts.afterRemoving(removed, from: song.playCount)
            }
        }
        save()
    }

    /// Loescht den Verlauf eines Songs, oder - ohne `songID` - die gesamte Hoerhistorie.
    @discardableResult
    func clearPlayHistory(songID: UUID? = nil) -> Int {
        let events = ((try? context.fetch(FetchDescriptor<PlayEvent>())) ?? []).filter { songID == nil || $0.songID == songID }
        removeEvents(events)
        return events.count
    }

    /// Wie viele Songs haben mehr Wiedergaben als `plays`? Basis fuer `SongRank`.
    func songsPlayedMore(than plays: Int) -> Int {
        (try? context.fetchCount(FetchDescriptor<Song>(predicate: #Predicate { $0.playCount > plays }))) ?? 0
    }

    func songCount() -> Int {
        (try? context.fetchCount(FetchDescriptor<Song>())) ?? 0
    }
}
