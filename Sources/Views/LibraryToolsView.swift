import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// Backup & Wartung: Export (JSON/CSV), Wiederherstellen aus einem Backup und der
// Bibliotheks-Check. Eigener Unterbildschirm, damit die Einstellungen ruhig bleiben.
struct LibraryToolsView: View {
    @EnvironmentObject private var store: EraStore
    @Query private var songs: [Song]
    @Query private var playlists: [Playlist]
    @State private var shareItem: ShareItem?
    @State private var showRestorePicker = false
    @State private var report: LibraryHealthReport?
    @State private var alert: ToolAlert?
    @State private var pending: PendingAction?
    @State private var exportFailed = false
    @State private var autoBackups: [AutoBackupFile] = []
    @State private var pendingAutoRestore: AutoBackupFile?
    @AppStorage(AppSettings.lastBackupKey) private var lastBackup = 0.0
    @AppStorage(AppSettings.autoBackupEnabledKey) private var autoBackupEnabled = true
    @AppStorage(AppSettings.ignoredSimilarKey) private var ignoredSimilarRaw = ""

    private var ignoredSimilar: Set<String> { Set(ignoredSimilarRaw.split(separator: "\n").map(String.init)) }

    private struct ToolAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private enum PendingAction: Identifiable {
        case removeMissing, deleteOrphans, merge(LibraryHealthReport.DuplicateGroup), mergeSimilar(LibraryHealthReport.DuplicateGroup),
             deduplicate(LibraryHealthReport.PlaylistDuplicate)
        var id: String {
            switch self {
            case .removeMissing: "missing"
            case .deleteOrphans: "orphans"
            case .merge(let group): "merge-\(group.songIDs.first?.uuidString ?? "")"
            case .mergeSimilar(let group): "similar-\(group.songIDs.first?.uuidString ?? "")"
            case .deduplicate(let group): "dedupe-\(group.playlistID.uuidString)"
            }
        }
    }

    var body: some View {
        List {
            Section {
                Button {
                    export {
                        let url = try BackupService.exportURL(store: store)
                        lastBackup = Date().timeIntervalSince1970
                        return url
                    }
                } label: {
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
                if lastBackup > 0 {
                    Text("Last backup: \(Date(timeIntervalSince1970: lastBackup).formatted(date: .abbreviated, time: .shortened))")
                }
                Text("Backups contain your library data, not the audio files. Restoring adds songs back whose audio is still on this device and never overwrites anything.")
            }

            Section {
                M3UImportButton(songs: songs, playlists: playlists)
            } header: {
                Text("Import")
            } footer: {
                Text("Import a playlist file (.m3u). Songs are matched by file name first, then by title and artist.")
            }

            Section {
                Toggle("Daily Automatic Backup", isOn: $autoBackupEnabled)
                ForEach(autoBackups) { file in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.date.formatted(date: .abbreviated, time: .shortened))
                            Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Button("Restore") { pendingAutoRestore = file }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                    .accessibilityElement(children: .combine)
                    .swipeActions(edge: .trailing) {
                        Button { shareItem = ShareItem(url: file.url) } label: { Label("Share", systemImage: "square.and.arrow.up") }
                            .tint(.accentColor)
                    }
                    .contextMenu {
                        Button { shareItem = ShareItem(url: file.url) } label: { Label("Share", systemImage: "square.and.arrow.up") }
                    }
                }
                Button {
                    if AutoBackupService.runIfDue(store: store, force: true) {
                        autoBackups = AutoBackupService.files()
                    } else {
                        exportFailed = true
                    }
                } label: { Label("Back Up Now", systemImage: "externaldrive.badge.plus") }
            } header: {
                Text("Automatic Backups")
            } footer: {
                Text("Era saves a backup on this device about once a day and keeps the last five. They survive a database reset. Swipe a backup to share it.")
            }

            Section {
                if let report {
                    let similar = report.visibleSimilar(ignoring: ignoredSimilar)
                    if report.isHealthy && similar.isEmpty {
                        Label("Everything looks good.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        findings(report, similar: similar)
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
        .task {
            autoBackups = AutoBackupService.files()
            if report == nil { runCheck() }
        }
        .sheet(item: $shareItem) { ShareSheet(items: [$0.url]) }
        // UIKit-Picker statt .fileImporter: Letzterer schliesst auf Geraeten oft nicht (siehe DocumentPicker).
        .sheet(isPresented: $showRestorePicker) {
            DocumentPicker(contentTypes: [.json], onPicked: { urls in
                showRestorePicker = false
                if let url = urls.first { restore(.success(url)) }
            }, onCancel: { showRestorePicker = false })
        }
        .confirmationDialog("Restore this backup?", isPresented: Binding(get: { pendingAutoRestore != nil }, set: { if !$0 { pendingAutoRestore = nil } }), titleVisibility: .visible) {
            Button("Restore") {
                if let file = pendingAutoRestore { restoreAuto(file) }
                pendingAutoRestore = nil
            }
            Button("Cancel", role: .cancel) { pendingAutoRestore = nil }
        } message: {
            Text("Missing songs are added back. Nothing existing is overwritten.")
        }
        .alert(item: $alert) { Alert(title: Text($0.title), message: Text($0.message), dismissButton: .default(Text("OK"))) }
        .alert("Backup Failed", isPresented: $exportFailed) { Button("OK", role: .cancel) {} }
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            Button(confirmButton, role: .destructive) { perform(pending); pending = nil }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { Text(confirmMessage) }
    }

    // MARK: Findings

    @ViewBuilder private func findings(_ report: LibraryHealthReport, similar: [LibraryHealthReport.DuplicateGroup]) -> some View {
        if !report.missingAudio.isEmpty {
            finding(String(localized: "\(report.missingAudio.count) missing audio files"), symbol: "exclamationmark.triangle.fill", tint: .orange,
                    detail: report.missingAudio.prefix(3).map { "\($0.title) (\($0.versionName))" }.joined(separator: ", ")
                        + "\n" + String(localized: "Importing the same files again relinks them."),
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
        ForEach(report.trackIssues, id: \.songIDs) { issue in
            if issue.fixableByRenumbering {
                finding(issue.album, symbol: "list.number", tint: .yellow,
                        detail: trackIssueDetail(issue),
                        action: String(localized: "Fix")) { store.renumberAlbum(songIDs: issue.songIDs); runCheck() }
            } else {
                // Nur fehlende Discs: Neunummerieren repariert nichts – Hinweis statt Fix-Knopf.
                finding(issue.album, symbol: "list.number", tint: .yellow,
                        detail: trackIssueDetail(issue) + "\n" + String(localized: "Renumbering can't fix this — the disc itself is missing. Import the missing disc to complete the album."))
            }
        }
        ForEach(report.playlistDuplicates, id: \.playlistID) { group in
            finding(group.playlistName, symbol: "music.note.list", tint: .purple,
                    detail: playlistDuplicateDetail(group),
                    action: String(localized: "Remove Duplicates")) { pending = .deduplicate(group) }
        }
        ForEach(report.duplicates, id: \.songIDs) { group in
            finding(group.title, symbol: "square.on.square", tint: .blue,
                    detail: String(localized: "\(group.songIDs.count) copies") + (group.artist.isEmpty ? "" : " · \(group.artist)"),
                    action: String(localized: "Merge")) { pending = .merge(group) }
        }
        if !report.duplicates.isEmpty {
            Button { showDuplicatesInSearch() } label: {
                Label("Show Duplicates in Search", systemImage: "magnifyingglass")
            }
        }
        ForEach(similar, id: \.songIDs) { group in
            finding(group.title, symbol: "rectangle.stack", tint: .teal,
                    detail: String(localized: "Looks like versions of one song · \(group.songIDs.count) songs"),
                    action: String(localized: "Merge")) { pending = .mergeSimilar(group) }
                .contextMenu {
                    Button { ignore(group) } label: { Label("Not the Same Song", systemImage: "eye.slash") }
                }
                .swipeActions {
                    Button { ignore(group) } label: { Label("Not the Same Song", systemImage: "eye.slash") }.tint(.gray)
                }
        }
    }

    private func playlistDuplicateDetail(_ group: LibraryHealthReport.PlaylistDuplicate) -> String {
        let names = group.songs.prefix(2).map { "\($0.title) (\($0.extraCount + 1)×)" }
        var text = names.joined(separator: ", ")
        if group.songs.count > 2 { text += ", …" }
        return text + "\n" + String(localized: "\(group.removedCount) duplicate entries")
    }

    private func trackIssueDetail(_ issue: LibraryHealthReport.TrackIssue) -> String {
        var parts: [String] = []
        if !issue.missingDiscs.isEmpty {
            parts.append(String(localized: "Missing disc: \(TrackNumberList.text(issue.missingDiscs))"))
        }
        if issue.discs.count > 1 || !issue.missingDiscs.isEmpty {
            for disc in issue.discs {
                var bits: [String] = []
                if !disc.missing.isEmpty { bits.append(String(localized: "Missing track numbers: \(TrackNumberList.text(disc.missing))")) }
                if !disc.duplicates.isEmpty { bits.append(String(localized: "Used twice: \(TrackNumberList.text(disc.duplicates))")) }
                parts.append(String(localized: "Disc \(disc.disc): \(bits.joined(separator: " · "))"))
            }
        } else {
            if !issue.missing.isEmpty { parts.append(String(localized: "Missing track numbers: \(TrackNumberList.text(issue.missing))")) }
            if !issue.duplicates.isEmpty { parts.append(String(localized: "Used twice: \(TrackNumberList.text(issue.duplicates))")) }
        }
        return parts.joined(separator: "\n")
    }

    private func ignore(_ group: LibraryHealthReport.DuplicateGroup) {
        let key = LibraryHealthReport.groupKey(group.songIDs)
        guard !ignoredSimilar.contains(key) else { return }
        ignoredSimilarRaw = (ignoredSimilarRaw.isEmpty ? "" : ignoredSimilarRaw + "\n") + key
    }

    private func finding(_ title: String, symbol: String, tint: Color, detail: String = "", action: String? = nil, perform: (() -> Void)? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
            }
            Spacer(minLength: 8)
            if let action, let perform {
                Button(action, action: perform).buttonStyle(.bordered).controlSize(.small)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    private func runCheck() { report = store.healthReport() }

    /// Springt in die Suche mit `duplicates:yes`: Die Suche liest die hinterlegte
    /// Anfrage beim Erscheinen und loescht sie danach (ein Tab-Wechsel allein uebergibt keine Anfrage).
    private func showDuplicatesInSearch() {
        UserDefaults.standard.set("duplicates:yes", forKey: AppSettings.pendingSearchQueryKey)
        NotificationCenter.default.post(name: .eraSwitchScreen, object: nil, userInfo: ["screen": AppScreen.search.rawValue])
    }

    private func export(_ make: () throws -> URL) {
        do { shareItem = ShareItem(url: try make()) } catch { exportFailed = true }
    }

    private func perform(_ action: PendingAction?) {
        guard let report, let action else { return }
        switch action {
        case .removeMissing: store.removeMissingAudio(report.missingAudio)
        case .deleteOrphans: store.deleteOrphans(audio: report.orphanAudioFiles, artwork: report.orphanArtworkFiles)
        case .merge(let group): store.mergeDuplicates(songIDs: group.songIDs)
        case .mergeSimilar(let group): store.mergeSimilar(songIDs: group.songIDs)
        case .deduplicate(let group): store.deduplicatePlaylist(playlistID: group.playlistID)
        }
        runCheck()
    }

    private var confirmTitle: String {
        switch pending {
        case .removeMissing: String(localized: "Remove Missing Entries?")
        case .deleteOrphans: String(localized: "Delete Unused Files?")
        case .merge: String(localized: "Merge Duplicates?")
        case .mergeSimilar: String(localized: "Merge as Versions?")
        case .deduplicate: String(localized: "Remove Duplicates?")
        case nil: ""
        }
    }
    private var confirmButton: String {
        switch pending {
        case .removeMissing: String(localized: "Remove")
        case .deleteOrphans: String(localized: "Delete")
        case .merge, .mergeSimilar: String(localized: "Merge")
        case .deduplicate: String(localized: "Remove")
        case nil: ""
        }
    }
    private var confirmMessage: String {
        switch pending {
        case .removeMissing: String(localized: "These versions cannot be played because their audio files are gone. They are removed from your library and playlists.")
        case .deleteOrphans: String(localized: "Files that no song uses are permanently deleted from this device.")
        case .merge: String(localized: "All copies become versions of one song.")
        case .mergeSimilar: String(localized: "The songs become versions of one song. Each keeps its original title as the version title.")
        case .deduplicate: String(localized: "Duplicate entries are removed from this playlist. The first entry of each song stays.")
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

    private func restoreAuto(_ file: AutoBackupFile) {
        do {
            let summary = try AutoBackupService.restore(file, into: store)
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
            if summary.playEvents > 0 { parts.append(String(localized: "\(summary.playEvents) plays")) }
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
