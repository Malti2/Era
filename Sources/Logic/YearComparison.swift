import Foundation

// Vergleich eines Jahresrueckblicks mit dem Vorjahr (reine Logik).
struct YearComparison: Equatable {
    let previousYear: Int
    let playsDelta: Int
    let secondsDelta: Double
    let activeDaysDelta: Int
    let newTracksDelta: Int
    /// Aenderung der Hoerzeit in Prozent; nil, wenn das Vorjahr keine Hoerzeit hatte.
    let secondsPercent: Int?

    /// nil, wenn es kein vergleichbares Vorjahr gibt (leer oder nicht frueher).
    static func make(current: YearReview, previous: YearReview) -> YearComparison? {
        guard !previous.isEmpty, !current.isEmpty, previous.year < current.year else { return nil }
        let percent: Int? = previous.seconds > 0
            ? Int(((current.seconds - previous.seconds) / previous.seconds * 100).rounded())
            : nil
        return YearComparison(
            previousYear: previous.year,
            playsDelta: current.plays - previous.plays,
            secondsDelta: current.seconds - previous.seconds,
            activeDaysDelta: current.activeDays - previous.activeDays,
            newTracksDelta: current.newTracks - previous.newTracks,
            secondsPercent: percent)
    }

    /// Vorzeichen-Darstellung: "+5", "−3" (echtes Minuszeichen), "0".
    static func signed(_ value: Int) -> String {
        switch value {
        case 0: return "0"
        case 1...: return "+\(value)"
        default: return "\u{2212}\(-value)"
        }
    }

    static func signedPercent(_ value: Int) -> String { signed(value) + " %" }
}
