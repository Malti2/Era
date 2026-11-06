import Foundation

// Restlaufzeit der Warteschlange ("5 Titel, 18 min"), ausgehend vom aktuellen Titel.
struct QueueSummary: Equatable {
    var upNextCount: Int
    var remainingSeconds: Double

    /// `durations` in Queue-Reihenfolge; `currentIndex` = laufender Titel (nil = nichts spielt,
    /// dann zaehlt alles als "als Naechstes"). `currentTime` kuerzt die Restzeit des laufenden Titels.
    static func make(durations: [Double], currentIndex: Int?, currentTime: Double) -> QueueSummary {
        guard let index = currentIndex, durations.indices.contains(index) else {
            return QueueSummary(upNextCount: durations.count, remainingSeconds: durations.reduce(0) { $0 + max(0, $1) })
        }
        let rest = durations[(index + 1)...].reduce(0) { $0 + max(0, $1) }
        let left = max(0, durations[index] - max(0, currentTime))
        return QueueSummary(upNextCount: durations.count - index - 1, remainingSeconds: rest + left)
    }
}
