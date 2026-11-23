import Foundation

// Woechentliches Hoerziel: Zielminuten pro Woche, Fortschritt aus den PlayEvents und
// Streak der Wochen in Folge, in denen das Ziel erreicht wurde. Fenster ist die
// Kalenderwoche (Montag-Sonntag) - passend zum "This Week"-Rhythmus der Home-Karte.
struct ListeningGoal: Equatable {
    /// Auswahl in den Einstellungen (Minuten pro Woche, 0 = aus).
    static let presets = [0, 60, 120, 300, 600]

    var minutesPerWeek: Int
    var secondsThisWeek: Double
    /// Wochen in Folge, in denen das Ziel erreicht wurde (rueckwaerts ab dieser Woche).
    var streak: Int

    var isEnabled: Bool { minutesPerWeek > 0 }
    var targetSeconds: Double { Double(minutesPerWeek) * 60 }
    var reached: Bool { isEnabled && secondsThisWeek >= targetSeconds }
    var progress: Double { isEnabled && targetSeconds > 0 ? min(1, secondsThisWeek / targetSeconds) : 0 }
    var remainingSeconds: Double { max(0, targetSeconds - secondsThisWeek) }

    static func make(minutesPerWeek: Int, from records: [PlayRecord], now: Date = Date(),
                     calendar: Calendar = .current) -> ListeningGoal {
        var seconds = 0.0
        if let week = calendar.dateInterval(of: .weekOfYear, for: now) {
            for record in records where week.contains(record.date) { seconds += record.seconds }
        }
        return ListeningGoal(minutesPerWeek: minutesPerWeek, secondsThisWeek: seconds,
                             streak: streak(minutesPerWeek: minutesPerWeek, from: records, now: now, calendar: calendar))
    }

    /// Zaehlt rueckwaerts ab der aktuellen Woche, wie viele Wochen in Folge das Ziel erreicht wurde.
    /// Ist die aktuelle Woche noch nicht erreicht, startet der Lauf in der Vorwoche.
    static func streak(minutesPerWeek: Int, from records: [PlayRecord], now: Date = Date(),
                       calendar: Calendar = .current) -> Int {
        guard minutesPerWeek > 0 else { return 0 }
        let target = Double(minutesPerWeek) * 60
        guard var week = calendar.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        var seconds = records.filter { week.contains($0.date) }.reduce(0) { $0 + $1.seconds }
        if seconds < target {
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: week.start),
                  let prevWeek = calendar.dateInterval(of: .weekOfYear, for: previous) else { return 0 }
            week = prevWeek
            seconds = records.filter { week.contains($0.date) }.reduce(0) { $0 + $1.seconds }
        }
        var count = 0
        while seconds >= target {
            count += 1
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: week.start),
                  let prevWeek = calendar.dateInterval(of: .weekOfYear, for: previous) else { break }
            week = prevWeek
            seconds = records.filter { week.contains($0.date) }.reduce(0) { $0 + $1.seconds }
        }
        return count
    }
}
