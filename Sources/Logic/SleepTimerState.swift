import Foundation

// Einschlaf-Timer als reine Zustandsmaschine: Countdown mit sanftem Ausblenden in
// den letzten Sekunden oder "bis zum Ende des Titels". Der Player ruft nur tick()
// im Sekundentakt und trackFinished() am Titelende auf.
struct SleepTimerState: Equatable {
    enum Mode: Equatable {
        case countdown(remaining: Int)
        case endOfTrack
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
    var stopsAtTrackEnd: Bool { mode == .endOfTrack }

    mutating func start(minutes: Int) { mode = minutes > 0 ? .countdown(remaining: minutes * 60) : nil }
    mutating func startEndOfTrack() { mode = .endOfTrack }
    mutating func cancel() { mode = nil }

    /// Ein Tick (Sekunde). `remainingSeconds` ist die Restzeit des laufenden Titels
    /// und nur im End-Of-Track-Modus relevant: dort blendet der Timer in den letzten
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
            guard let remaining = remainingSeconds, remaining > 0 else { return .none }
            return remaining <= Double(Self.fadeSeconds) ? .fade(Float(remaining) / Float(Self.fadeSeconds)) : .none
        }
    }

    /// true = Wiedergabe soll jetzt enden (statt zum naechsten Titel zu wechseln).
    mutating func trackFinished() -> Bool {
        guard mode == .endOfTrack else { return false }
        mode = nil
        return true
    }
}
