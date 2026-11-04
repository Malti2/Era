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
        for event in events { context.delete(event) }
        if !events.isEmpty { save() }
        return events.count
    }

    /// Loescht den Verlauf eines Songs, oder - ohne `songID` - die gesamte Hoerhistorie.
    @discardableResult
    func clearPlayHistory(songID: UUID? = nil) -> Int {
        let events = ((try? context.fetch(FetchDescriptor<PlayEvent>())) ?? []).filter { songID == nil || $0.songID == songID }
        for event in events { context.delete(event) }
        if !events.isEmpty { save() }
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
