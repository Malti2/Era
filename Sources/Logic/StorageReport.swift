import Foundation

// Speicher-Uebersicht der Audiodateien: Gesamtgroesse, groesste Dateien, Verteilung nach Format.
// Reine Logik auf Snapshots; die Dateigroessen liest die View ausserhalb des Main-Threads.

struct StorageItem: Equatable, Identifiable {
    var id: UUID
    var songID: UUID
    var title: String
    var versionName: String
    var fileExtension: String
    /// nil = Datei fehlt auf dem Geraet
    var bytes: Int64?
    /// Hauptversion des Songs (wird beim Aufraeumen nie vorgeschlagen).
    var isPrimary = true
    /// Wie viele Versionen der Song insgesamt hat.
    var siblingCount = 1
}

struct StorageReport: Equatable {
    struct Format: Equatable, Identifiable {
        var name: String
        var count: Int
        var bytes: Int64
        var id: String { name }
    }

    var totalBytes: Int64 = 0
    var fileCount = 0
    var missingCount = 0
    var formats: [Format] = []
    var largest: [StorageItem] = []

    var isEmpty: Bool { fileCount == 0 && missingCount == 0 }
    var averageBytes: Int64 { fileCount > 0 ? totalBytes / Int64(fileCount) : 0 }

    static func make(from items: [StorageItem], largestLimit: Int = 5) -> StorageReport {
        var report = StorageReport()
        var byFormat: [String: Format] = [:]
        var present: [StorageItem] = []
        for item in items {
            guard let bytes = item.bytes else { report.missingCount += 1; continue }
            report.fileCount += 1
            report.totalBytes += bytes
            present.append(item)
            let name = item.fileExtension.isEmpty ? "?" : item.fileExtension.uppercased()
            var format = byFormat[name] ?? Format(name: name, count: 0, bytes: 0)
            format.count += 1
            format.bytes += bytes
            byFormat[name] = format
        }
        report.formats = byFormat.values.sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.name < $1.name }
        report.largest = Array(present.sorted {
            let l = $0.bytes ?? 0, r = $1.bytes ?? 0
            return l != r ? l > r : $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }.prefix(largestLimit))
        return report
    }

    /// Anteil von `bytes` an der Gesamtgroesse (0...1), fuer Balken.
    func share(of bytes: Int64) -> Double {
        totalBytes > 0 ? Double(bytes) / Double(totalBytes) : 0
    }
}

/// Aufraeum-Vorschlaege: alternative Versionen (nicht die Hauptversion), groesste zuerst.
/// Die Hauptversion und der letzte verbleibende Titel eines Songs werden nie angeboten.
struct StorageCleanup: Equatable {
    var candidates: [StorageItem] = []

    var reclaimableBytes: Int64 { candidates.reduce(0) { $0 + ($1.bytes ?? 0) } }
    var isEmpty: Bool { candidates.isEmpty }

    static func make(from items: [StorageItem]) -> StorageCleanup {
        let list = items.filter { !$0.isPrimary && $0.siblingCount > 1 && ($0.bytes ?? 0) > 0 }
            .sorted {
                let l = $0.bytes ?? 0, r = $1.bytes ?? 0
                if l != r { return l > r }
                let order = $0.title.localizedStandardCompare($1.title)
                return order != .orderedSame ? order == .orderedAscending : $0.versionName < $1.versionName
            }
        return StorageCleanup(candidates: list)
    }

    func bytes(of ids: Set<UUID>) -> Int64 {
        candidates.filter { ids.contains($0.id) }.reduce(0) { $0 + ($1.bytes ?? 0) }
    }

    /// Alle Kandidaten, die mindestens `minBytes` gross sind (fuer "Grosse Alternativen auswaehlen").
    func ids(atLeast minBytes: Int64) -> Set<UUID> {
        Set(candidates.filter { ($0.bytes ?? 0) >= minBytes }.map(\.id))
    }
}
