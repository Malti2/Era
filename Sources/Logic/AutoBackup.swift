import Foundation

// Automatische, lokale Sicherungen: hoechstens eine pro Tag, die letzten fuenf bleiben.
// Dateiname traegt den Zeitstempel (UTC), damit Sortieren und Aufraeumen ohne
// Dateisystem-Metadaten funktioniert. Reine Logik, ohne SwiftData.
enum AutoBackup {
    static let keepCount = 5
    static let minInterval: TimeInterval = 20 * 3600
    private static let prefix = "Era-Auto-"
    private static let suffix = ".json"

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let text = String(value)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }

    static func fileName(for date: Date) -> String {
        let c = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let day = pad(c.year ?? 0, 4) + pad(c.month ?? 0, 2) + pad(c.day ?? 0, 2)
        let time = pad(c.hour ?? 0, 2) + pad(c.minute ?? 0, 2) + pad(c.second ?? 0, 2)
        return "\(prefix)\(day)-\(time)\(suffix)"
    }

    static func date(fromFileName name: String) -> Date? {
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return nil }
        let stamp = name.dropFirst(prefix.count).dropLast(suffix.count)
        let parts = stamp.split(separator: "-")
        guard parts.count == 2, parts[0].count == 8, parts[1].count == 6,
              let day = Int(parts[0]), let time = Int(parts[1]) else { return nil }
        let components = DateComponents(year: day / 10_000, month: day / 100 % 100, day: day % 100,
                                        hour: time / 10_000, minute: time / 100 % 100, second: time % 100)
        return utc.date(from: components)
    }

    /// Empty libraries are never backed up: that would push real backups out after a reset.
    /// `force` (manual "Back Up Now") skips the interval, `enabled == false` (user switched it off) skips everything.
    static func isDue(songCount: Int, lastBackup: Date?, now: Date = Date(), enabled: Bool = true, force: Bool = false) -> Bool {
        guard enabled, songCount > 0 else { return false }
        if force { return true }
        guard let lastBackup else { return true }
        return now.timeIntervalSince(lastBackup) >= minInterval
    }

    /// Valid backup names, newest first. Foreign files are ignored.
    static func sorted(_ names: [String]) -> [String] {
        names.compactMap { name in date(fromFileName: name).map { (name, $0) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    /// Names to delete so only the newest `keep` remain.
    static func namesToPrune(_ names: [String], keep: Int = keepCount) -> [String] {
        Array(sorted(names).dropFirst(max(1, keep)))
    }
}
