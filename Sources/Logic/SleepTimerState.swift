import Foundation

// Einschlaf-Timer als reine Zustandsmaschine: Countdown mit sanftem Ausblenden in
// den letzten Sekunden, "bis zum Ende des Titels" oder "nach N Titeln". Der Player ruft nur tick()
// im Sekundentakt und trackFinished() am Titelende (bzw. songSkipped() beim manuellen
// Weiterspringen) auf.
struct SleepTimerState: Equatable {
    enum Mode: Equatable {
        case countdown(remaining: Int)
        case endOfTrack
        /// Zaehlt inklusive des laufenden Titels: 1 stoppt nach diesem Titel.
        case afterSongs(remaining: Int)
    }

    enum Event: Equatable {
        case none
        /// Lautstaerke 0...1 waehrend des Ausblendens
        case fade(Float)
        case expired
    }

    static let fadeSeconds = 5

    private(set) var mode: Mode?

    var isActive: Bool { mode != nil }
    var remaining: Int? {
        if case .countdown(let seconds) = mode { return seconds }
        return nil
    }
    var remainingSongs: Int? {
        if case .afterSongs(let count) = mode { return count }
        return nil
    }
    var stopsAtTrackEnd: Bool { mode == .endOfTrack }
    /// Der laufende Titel ist der letzte gezaehlte: kein naechster Titel vorladen,
    /// in den letzten Sekunden ausblenden.
    var isLastSong: Bool {
        if case .afterSongs(let count) = mode { return count <= 1 }
        return false
    }
    var fadesAtTrackEnd: Bool { stopsAtTrackEnd || isLastSong }

    mutating func start(minutes: Int) { mode = minutes > 0 ? .countdown(remaining: minutes * 60) : nil }
    mutating func startEndOfTrack() { mode = .endOfTrack }
    mutating func startAfterSongs(_ count: Int) { mode = count > 0 ? .afterSongs(remaining: count) : nil }
    mutating func cancel() { mode = nil }

    /// Verlaengert einen laufenden Countdown um `minutes` (End-Of-Track, Nach-N-Titeln
    /// und inaktiver Timer: nichts zu verlaengern).
    mutating func extend(minutes: Int) {
        guard case .countdown(let seconds) = mode, minutes > 0 else { return }
        mode = .countdown(remaining: seconds + minutes * 60)
    }

    /// Ein Tick (Sekunde). `remainingSeconds` ist die Restzeit des laufenden Titels
    /// und nur in den Modi relevant, die am Titelende stoppen: dort blendet der Timer in den letzten
    /// `fadeSeconds` aus, statt abrupt zu stoppen. Der Countdown-Modus ignoriert den Wert.
    mutating func tick(remainingSeconds: Double? = nil) -> Event {
        switch mode {
        case .none:
            return .none
        case .countdown(let seconds):
            let left = seconds - 1
            if left <= 0 {
                mode = nil
                return .expired
            }
            mode = .countdown(remaining: left)
            return left <= Self.fadeSeconds ? .fade(Float(left) / Float(Self.fadeSeconds)) : .none
        case .endOfTrack:
            return Self.fadeEvent(remainingSeconds: remainingSeconds)
        case .afterSongs(let count):
            guard count <= 1 else { return .none }
            return Self.fadeEvent(remainingSeconds: remainingSeconds)
        }
    }

    private static func fadeEvent(remainingSeconds: Double?) -> Event {
        guard let remaining = remainingSeconds, remaining > 0 else { return .none }
        return remaining <= Double(Self.fadeSeconds) ? .fade(Float(remaining) / Float(Self.fadeSeconds)) : .none
    }

    /// true = Wiedergabe soll jetzt enden (statt zum naechsten Titel zu wechseln).
    mutating func trackFinished() -> Bool {
        switch mode {
        case .endOfTrack:
            mode = nil
            return true
        case .afterSongs:
            return advanceSongCount()
        default:
            return false
        }
    }

    /// Manuelles Weiterspringen zaehlt wie ein gehoerter Titel (gleiche Regel wie
    /// `trackFinished`, aber nur im Nach-N-Titeln-Modus: beim Countdown und bei
    /// "bis Titelende" aendert ein Skip nichts). Zurueckspringen zaehlt nie.
    mutating func songSkipped() -> Bool {
        guard case .afterSongs = mode else { return false }
        return advanceSongCount()
    }

    /// Zaehlt einen Titel herunter. true = der Zaehler ist bei 0 angekommen.
    private mutating func advanceSongCount() -> Bool {
        guard case .afterSongs(let count) = mode else { return false }
        if count <= 1 {
            mode = nil
            return true
        }
        mode = .afterSongs(remaining: count - 1)
        return false
    }
}
