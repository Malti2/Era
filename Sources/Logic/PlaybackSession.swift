import Foundation

// Merkt sich Warteschlange und Position ueber App-Starts hinweg. Gespeichert werden nur
// Version-IDs; beim Wiederherstellen wird gegen die vorhandenen Versionen abgeglichen.
struct PlaybackSnapshot: Codable, Equatable {
    var queue: [UUID]
    var current: UUID
    var position: Double
    var shuffle: Bool
    var repeatMode: Int

    struct Restored: Equatable {
        var queue: [UUID]
        var current: UUID
        var position: Double
    }

    /// Entfernt verschwundene Versionen. Ist die aktuelle weg, rueckt der naechste
    /// noch vorhandene Titel nach (Position dann 0). Nil, wenn nichts uebrig bleibt.
    func restored(available: Set<UUID>, durations: [UUID: Double] = [:]) -> Restored? {
        let kept = queue.filter { available.contains($0) }
        guard !kept.isEmpty else { return nil }
        if available.contains(current), kept.contains(current) {
            return Restored(queue: kept, current: current, position: Self.clamp(position, duration: durations[current]))
        }
        let originalIndex = queue.firstIndex(of: current) ?? 0
        let next = queue[originalIndex...].first { available.contains($0) } ?? kept[0]
        return Restored(queue: kept, current: next, position: 0)
    }

    /// Ganz am Anfang oder Ende lohnt kein Wiederaufsetzen.
    static func clamp(_ position: Double, duration: Double?) -> Double {
        guard position.isFinite, position > 3 else { return 0 }
        if let duration, duration > 0, position > duration - 3 { return 0 }
        return position
    }

    static let storageKey = "player.session"

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }

    static func load(from defaults: UserDefaults = .standard) -> PlaybackSnapshot? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(PlaybackSnapshot.self, from: data)
    }
}

// Zufallswiedergabe ohne Wiederholung: jeder Titel kommt einmal dran, bevor ein
// Durchlauf neu beginnt; "Zurueck" geht die gespielte Reihenfolge rueckwaerts.
struct ShuffleBag: Equatable {
    private(set) var played: [UUID] = []

    mutating func reset(startingWith id: UUID? = nil) { played = id.map { [$0] } ?? [] }

    /// Naechster Titel. Nil = Durchlauf beendet und `wrap` ist false.
    mutating func next<G: RandomNumberGenerator>(in queue: [UUID], current: UUID, wrap: Bool, using generator: inout G) -> UUID? {
        if played.last != current { played.append(current) }
        let playedSet = Set(played)
        var candidates = queue.filter { !playedSet.contains($0) }
        if candidates.isEmpty {
            guard wrap else { return nil }
            played = [current]
            candidates = queue.filter { $0 != current }
            if candidates.isEmpty { candidates = queue }
        }
        guard let pick = candidates.randomElement(using: &generator) else { return nil }
        played.append(pick)
        return pick
    }

    mutating func next(in queue: [UUID], current: UUID, wrap: Bool) -> UUID? {
        var generator = SystemRandomNumberGenerator()
        return next(in: queue, current: current, wrap: wrap, using: &generator)
    }

    /// Vorheriger gespielter Titel, falls es einen gibt (der aktuelle wird aus der Historie genommen).
    mutating func previous(current: UUID) -> UUID? {
        if played.last == current { played.removeLast() }
        guard let last = played.popLast() else { return nil }
        played.append(last)
        return last
    }
}
