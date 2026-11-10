import Foundation

// A/B-Vergleich: beim Wechsel zwischen Versionen desselben Songs soll die Hoerposition erhalten bleiben,
// damit man dieselbe Stelle in Demo und Final direkt vergleichen kann. Reine Foundation-Logik.

enum VersionSwitch {
    /// Bis zu diesem relativen Laengenunterschied gelten die Versionen als zeitlich deckungsgleich (gleiche Sekunde).
    static let alignedTolerance = 0.15
    /// Abstand zum Ende, damit der Vergleich nicht sofort in den naechsten Titel laeuft.
    static let endMargin = 1.0

    /// Zielposition in der neuen Version. Aehnlich lange Versionen behalten die absolute Zeit,
    /// stark abweichende (z. B. Radio Edit vs. Extended) den relativen Fortschritt.
    static func position(time: Double, from oldDuration: Double, to newDuration: Double) -> Double {
        guard time > 0, newDuration > 0 else { return 0 }
        let upper = max(0, newDuration - endMargin)
        guard oldDuration > 0 else { return min(time, upper) }
        let difference = abs(newDuration - oldDuration) / max(oldDuration, newDuration)
        let target = difference <= alignedTolerance ? time : time / oldDuration * newDuration
        return min(max(0, target), upper)
    }

    /// Kurzer Hinweis unter dem Versionsnamen, z. B. "Demo ⇄ Final".
    static func pairLabel(_ a: String, _ b: String) -> String { "\(a) ⇄ \(b)" }
}
