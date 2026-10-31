import Foundation

// Sanfte Erinnerung an ein Backup: erst ab einer Bibliothek, die sich zu sichern lohnt,
// und nie penetrant - "Spaeter" schiebt die Karte um zwei Wochen.
enum BackupReminder {
    static let minSongs = 10
    static let intervalDays = 30
    static let snoozeDays = 14

    /// `libraryStarted` = aeltestes Hinzufuegedatum; gilt als Bezug, solange noch nie gesichert wurde.
    static func isDue(songCount: Int, lastBackup: Date?, libraryStarted: Date?, snoozedUntil: Date?, now: Date = Date()) -> Bool {
        guard songCount >= minSongs else { return false }
        if let snoozedUntil, snoozedUntil > now { return false }
        guard let reference = lastBackup ?? libraryStarted else { return false }
        return now.timeIntervalSince(reference) >= Double(intervalDays) * 86_400
    }

    static func snoozeDate(from now: Date = Date()) -> Date {
        now.addingTimeInterval(Double(snoozeDays) * 86_400)
    }

    /// Ganze Tage seit dem Backup, nil wenn es keins gibt.
    static func daysSince(_ backup: Date?, now: Date = Date()) -> Int? {
        backup.map { max(0, Int(now.timeIntervalSince($0) / 86_400)) }
    }
}
