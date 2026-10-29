import Foundation

// A-B-Loop fuer Demos: Anfang und Ende markieren, dazwischen wiederholen.
// Ein Knopf schaltet reihum: aus -> A gesetzt -> Loop aktiv -> aus.
struct ABLoop: Equatable {
    enum Stage: Equatable { case off, startSet, active }

    /// Shorter loops are refused - they would stutter instead of repeat.
    static let minLength = 1.0
    /// Positions this far past B count as a deliberate seek, not as playback reaching B.
    static let catchWindow = 1.5

    private(set) var start: Double?
    private(set) var end: Double?

    var stage: Stage {
        switch (start, end) {
        case (nil, _): .off
        case (_?, nil): .startSet
        case (_?, _?): .active
        }
    }
    var isActive: Bool { stage == .active }

    /// Marks A, then B at `time`. A B too close to A is refused (returns false) so the user can try again.
    @discardableResult
    mutating func advance(at time: Double, duration: Double) -> Bool {
        switch stage {
        case .off:
            start = max(0, time)
            return true
        case .startSet:
            guard let start else { return false }
            let target = min(time, max(0, duration - 0.3))
            guard target - start >= ABLoop.minLength else { return false }
            end = target
            return true
        case .active:
            clear()
            return true
        }
    }

    mutating func clear() {
        start = nil
        end = nil
    }

    /// Where playback must jump to, if `time` has just run past the end of an active loop.
    func jumpTarget(for time: Double) -> Double? {
        guard let start, let end, time >= end, time < end + ABLoop.catchWindow else { return nil }
        return start
    }
}
