import Foundation
import SwiftData

// Track-Nummern: Reihenfolge innerhalb eines Albums.
extension Song {
    var trackItem: TrackItem { TrackItem(id: id, trackNumber: trackNumber, title: title, dateAdded: dateAdded) }
}

extension EraStore {
    /// Songs in Album-Reihenfolge (nummeriert zuerst, dann Import-Reihenfolge).
    static func inTrackOrder(_ songs: [Song]) -> [Song] {
        var byID: [UUID: Song] = [:]
        for song in songs where byID[song.id] == nil { byID[song.id] = song }
        return TrackOrder.sorted(songs.map(\.trackItem)).compactMap { byID[$0] }
    }

    /// Vergibt 1...n in der gegebenen Reihenfolge. Gibt zurueck, wie viele Songs sich geaendert haben.
    @discardableResult
    func applyTrackOrder(_ ordered: [Song]) -> Int {
        let songs = ordered.map { resolve($0) }
        var current: [UUID: Int] = [:]
        for song in songs { current[song.id] = song.trackNumber }
        let changes = TrackOrder.renumbered(order: songs.map(\.id), current: current)
        guard !changes.isEmpty else { return 0 }
        for song in songs { if let number = changes[song.id] { song.trackNumber = number } }
        save()
        return changes.count
    }

    /// Entfernt alle Nummern der Songs (zurueck zur Import-Reihenfolge).
    @discardableResult
    func clearTrackNumbers(of songs: [Song]) -> Int {
        let targets = songs.map { resolve($0) }.filter { $0.trackNumber != 0 }
        guard !targets.isEmpty else { return 0 }
        for song in targets { song.trackNumber = 0 }
        save()
        return targets.count
    }
}
