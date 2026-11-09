import Foundation
import os

// Schreibt taeglich (hoechstens) ein JSON-Backup in den App-Container. Der Ordner liegt
// neben, nicht in der Datenbank - ein Schema-Reset (siehe Persistence.makeContainer) laesst
// ihn unangetastet, und die Bibliothek ist damit per Tipp wiederherstellbar.
struct AutoBackupFile: Identifiable {
    let url: URL
    let date: Date
    var id: URL { url }
    var size: Int64 { Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
}

enum AutoBackupService {
    private static let log = Logger(subsystem: "de.malte.era", category: "autobackup")

    static var directory: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EraBackups", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func files(in directory: URL = directory) -> [AutoBackupFile] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return AutoBackup.sorted(names).compactMap { name in
            AutoBackup.date(fromFileName: name).map { AutoBackupFile(url: directory.appendingPathComponent(name), date: $0) }
        }
    }

    /// Creates a backup when the last one is old enough. Cheap no-op otherwise.
    @MainActor
    @discardableResult
    static func runIfDue(store: EraStore, now: Date = Date(), directory: URL = directory, force: Bool = false) -> Bool {
        let songCount = (try? store.allSongs().count) ?? 0
        let enabled = force || AppSettings.bool(AppSettings.autoBackupEnabledKey)
        guard AutoBackup.isDue(songCount: songCount, lastBackup: files(in: directory).first?.date, now: now,
                               enabled: enabled, force: force) else { return false }
        do {
            let temp = try BackupService.exportURL(store: store)
            let target = directory.appendingPathComponent(AutoBackup.fileName(for: now))
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: temp, to: target)
            for name in AutoBackup.namesToPrune(files(in: directory).map { $0.url.lastPathComponent }) {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
            }
            return true
        } catch {
            log.error("auto backup failed: \(error.localizedDescription)")
            return false
        }
    }

    @MainActor
    static func restore(_ file: AutoBackupFile, into store: EraStore) throws -> RestoreSummary {
        try BackupService.restore(from: try Data(contentsOf: file.url), into: store)
    }
}
