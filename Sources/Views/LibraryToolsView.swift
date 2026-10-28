import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// Backup & Wartung: Export (JSON/CSV), Wiederherstellen aus einem Backup und der
// Bibliotheks-Check. Eigener Unterbildschirm, damit die Einstellungen ruhig bleiben.
struct LibraryToolsView: View {
    @EnvironmentObject private var store: EraStore
    @State private var shareItem: ShareItem?
    @State private var showRestorePicker = false
    @State private var report: LibraryHealthReport?
    @State private var alert: ToolAlert?
    @State private var pending: PendingAction?
    @State private var exportFailed = false

    private struct ToolAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private enum PendingAction: Identifiable {
        case removeMissing, deleteOrphans, merge(LibraryHealthReport.DuplicateGroup)
        var id: String {
            switch self {
            case .removeMissing: "missing"
            case .deleteOrphans: "orphans"
            case .merge(let group): "merge-\(group.songIDs.first?.uuidString ?? "")"
            }
        }
    }

    var body: some View {
        List {
            Section {
                Button { export { try BackupService.exportURL(store: store) } } label: {
                    Label("Export Library (JSON)", systemImage: "square.and.arrow.up.on.square")
                }
                Button { export { try CSVExport.exportURL(store: store) } } label: {
                    Label("Export Library (CSV)", systemImage: "tablecells")
                }
                Button { showRestorePicker = true } label: {
                    Label("Restore from Backup…", systemImage: "arrow.counterclockwise.circle")
                }
            } header: {
                Text("Backup")
            } footer: {
                Text("Backups contain your library data, not the audio files. Restoring adds songs back whose audio is still on this device and never overwrites anything.")
            }

            Section {
                if let report {
                    if report.isHealthy {
                        Label("Everything looks good.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        findings(report)
                    }
                } else {
                    HStack { ProgressView(); Text("Checking…").foregroundStyle(.secondary) }
                }
                Button { runCheck() } label: { Label("Check Again", systemImage: "arrow.clockwise") }
            } header: {
                Text("Library Check")
            }
        }
        .navigationTitle("Backup & Maintenance")
        .navigationBarTitleDisplayMode(.inline)
        .task { if report == nil { runCheck() } }
        .sheet(item: $shareItem) { ShareSheet(items: [$0.url]) }
        .fileImporter(isPresented: $showRestorePicker, allowedContentTypes: [.json]) { result in restore(result) }
        .alert(item: $alert) { Alert(title: Text($0.title), message: Text($0.message), dismissButton: .default(Text("OK"))) }
        .alert("Backup Failed", isPresented: $exportFailed) { Button("OK", role: .cancel) {} }
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            Button(confirmButton, role: .destructive) { perform(pending); pending = nil }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { Text(confirmMessage) }
    }

    // MARK: Findings

    @ViewBuilder private func findings(_ report: LibraryHealthReport) -> some View {
        if !report.missingAudio.isEmpty {
            finding(String(localized: "\(report.missingAudio.count) missing audio files"), symbol: "exclamationmark.triangle.fill", tint: .orange,
                    detail: report.missingAudio.prefix(3).map { "\($0.title) (\($0.versionName))" }.joined(separator: ", "),
                    action: String(localized: "Remove")) { pending = .removeMissing }
        }
        if !report.emptySongIDs.isEmpty {
            finding(String(localized: "\(report.emptySongIDs.count) songs without versions"), symbol: "questionmark.folder", tint: .orange,
                    action: String(localized: "Remove")) { store.removeEmptySongs(); runCheck() }
        }
        if !report.brokenArtworkVersionIDs.isEmpty {
            finding(String(localized: "\(report.brokenArtworkVersionIDs.count) broken artwork links"), symbol: "photo.badge.exclamationmark", tint: .yellow,
                    action: String(localized: "Fix")) { store.clearBrokenArtwork(versionIDs: report.brokenArtworkVersionIDs); runCheck() }
        }
        if report.orphanCount > 0 {
            finding(String(localized: "\(report.orphanCount) unused files"), symbol: "doc.badge.ellipsis", tint: .secondary,
                    detail: ByteCountFormatter.string(fromByteCount: Int64(report.orphanBytes), countStyle: .file),
                    action: String(localized: "Delete")) { pending = .deleteOrphans }
        }
        ForEach(report.duplicates, id: \.songIDs) { group in
            finding(group.title, symbol: "square.on.square", tint: .blue,
                    detail: String(localized: "\(group.songIDs.count) copies") + (group.artist.isEmpty ? "" : " · \(group.artist)"),
                    action: String(localized: "Merge")) { pending = .merge(group) }
        }
    }

    private func finding(_ title: String, symbol: String, tint: Color, detail: String = "", action: String, perform: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer(minLength: 8)
            Button(action, action: perform).buttonStyle(.bordered).controlSize(.small)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    private func runCheck() { report = store.healthReport() }

    private func export(_ make: () throws -> URL) {
        do { shareItem = ShareItem(url: try make()) } catch { exportFailed = true }
    }

    private func perform(_ action: PendingAction?) {
        guard let report, let action else { return }
        switch action {
        case .removeMissing: store.removeMissingAudio(report.missingAudio)
        case .deleteOrphans: store.deleteOrphans(audio: report.orphanAudioFiles, artwork: report.orphanArtworkFiles)
        case .merge(let group): store.mergeDuplicates(songIDs: group.songIDs)
        }
        runCheck()
    }

    private var confirmTitle: String {
        switch pending {
        case .removeMissing: String(localized: "Remove Missing Entries?")
        case .deleteOrphans: String(localized: "Delete Unused Files?")
        case .merge: String(localized: "Merge Duplicates?")
        case nil: ""
        }
    }
    private var confirmButton: String {
        switch pending {
        case .removeMissing: String(localized: "Remove")
        case .deleteOrphans: String(localized: "Delete")
        case .merge: String(localized: "Merge")
        case nil: ""
        }
    }
    private var confirmMessage: String {
        switch pending {
        case .removeMissing: String(localized: "These versions cannot be played because their audio files are gone. They are removed from your library and playlists.")
        case .deleteOrphans: String(localized: "Files that no song uses are permanently deleted from this device.")
        case .merge: String(localized: "All copies become versions of one song.")
        case nil: ""
        }
    }

    private func restore(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let summary = try BackupService.restore(from: try Data(contentsOf: url), into: store)
            alert = ToolAlert(title: String(localized: "Restore Finished"), message: Self.message(for: summary))
            runCheck()
        } catch let error as BackupError {
            alert = ToolAlert(title: String(localized: "Restore Failed"), message: Self.message(for: error))
        } catch {
            alert = ToolAlert(title: String(localized: "Restore Failed"), message: error.localizedDescription)
        }
    }

    static func message(for summary: RestoreSummary) -> String {
        var lines: [String] = []
        if summary.restoredAnything {
            var parts = [String(localized: "\(summary.songs) songs")]
            if summary.playlists > 0 { parts.append(String(localized: "\(summary.playlists) playlists")) }
            if summary.packs > 0 { parts.append(String(localized: "\(summary.packs) collections")) }
            lines.append(String(localized: "Restored: \(parts.joined(separator: ", "))"))
        } else if summary.skippedMissingAudio == 0 {
            lines.append(String(localized: "Nothing to restore. Your library already contains everything from this backup."))
        }
        if summary.skippedMissingAudio > 0 {
            lines.append(String(localized: "\(summary.skippedMissingAudio) versions skipped: audio file not found on this device."))
        }
        return lines.joined(separator: "\n")
    }

    static func message(for error: BackupError) -> String {
        switch error {
        case .unreadable: String(localized: "This file could not be read as an Era backup.")
        case .notAnEraBackup: String(localized: "This file is not an Era backup.")
        case .newerFormat: String(localized: "This backup was made with a newer version of Era.")
        }
    }
}
