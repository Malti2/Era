import SwiftUI
import SwiftData

// Massenimport (Spec 4): viele Dateien auf einmal, Zuordnung und Tagging direkt
// in der Liste, ein Durchgang zum Bestaetigen. Traegt auch Bulk-Tagging.
struct MassImportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: EraStore
    @EnvironmentObject private var importer: ImportManager
    @Query private var songs: [Song]
    @Query private var tags: [Tag]

    @State private var bulkStatus: String = ""
    @State private var bulkTag = ""
    @State private var showFilePicker = false

    private var statusNames: [String] { tags.filter { $0.isStatus }.map(\.name) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { showFilePicker = true } label: {
                        Label("Add Files", systemImage: "plus")
                    }
                }

                if !importer.staged.isEmpty {
                    Section("For All") {
                        Picker("Status", selection: $bulkStatus) {
                            Text("No Status").tag("")
                            ForEach(statusNames, id: \.self) { Text($0).tag($0) }
                        }
                        HStack {
                            TextField("Tag for All", text: $bulkTag)
                            Button {
                                applyBulk()
                            } label: { Image(systemName: "arrow.down.circle.fill") }
                            .disabled(bulkTag.trimmingCharacters(in: .whitespaces).isEmpty && bulkStatus.isEmpty)
                        }
                    }

                    Section("\(importer.staged.count) files") {
                        ForEach($importer.staged) { $item in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(item.title).font(.body.weight(.medium)).lineLimit(1)
                                    Spacer()
                                    if let error = item.error {
                                        Text(error).font(.caption).foregroundStyle(.red).lineLimit(1)
                                    }
                                }
                                Text(item.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                if item.error == nil {
                                    HStack(spacing: 8) {
                                        Menu {
                                            Button("New Song") { item.linkToSongID = nil }
                                            Divider()
                                            if let suggested = item.suggestedSongID, let match = songs.first(where: { $0.id == suggested }) {
                                                Button("Suggestion: \(match.title)") { item.linkToSongID = match.id }
                                                Divider()
                                            }
                                            ForEach(songs) { s in
                                                Button(s.title) { item.linkToSongID = s.id }
                                            }
                                        } label: {
                                            Label(linkLabel(item), systemImage: "link")
                                                .font(.caption.weight(.medium))
                                        }
                                        if item.linkToSongID != nil {
                                            Menu {
                                                ForEach(VersionPreset.all, id: \.self) { preset in
                                                    Button(preset) { item.versionName = preset }
                                                }
                                            } label: {
                                                Text(item.versionName)
                                                    .font(.caption.weight(.medium))
                                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                                    .background(Color(.tertiarySystemFill), in: .capsule)
                                            }
                                        }
                                    }
                                    if let suggested = item.suggestedSongID, item.linkToSongID == nil,
                                       let match = songs.first(where: { $0.id == suggested }) {
                                        Button {
                                            item.linkToSongID = match.id
                                        } label: {
                                            Text("Does this belong to “\(match.title)”? Tap to link it")
                                                .font(.caption)
                                                .foregroundStyle(Color.accentColor)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.vertical, 3)
                        }
                        .onDelete { importer.staged.remove(atOffsets: $0) }
                    }
                }
            }
            .navigationTitle("Bulk Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { importer.staged = []; dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Import (\(importer.staged.filter { $0.error == nil }.count))") {
                        Task {
                            await importer.confirmStaged(into: store, songs: songs)
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(importer.staged.filter { $0.error == nil }.isEmpty)
                }
            }
            .sheet(isPresented: $showFilePicker) {
                DocumentPicker(contentTypes: ImportManager.importableTypes) { urls in
                    showFilePicker = false
                    Task { await importer.stage(urls, existing: songs) }
                } onCancel: { showFilePicker = false }
            }
        }
    }

    private func linkLabel(_ item: StagedImport) -> String {
        if let id = item.linkToSongID, let song = songs.first(where: { $0.id == id }) {
            return "Version of “\(song.title)”"
        }
        return "New Song"
    }

    private func applyBulk() {
        let status = bulkStatus
        let tagName = bulkTag.trimmingCharacters(in: .whitespaces)
        for i in importer.staged.indices where importer.staged[i].error == nil {
            if !status.isEmpty { importer.staged[i].statusName = status }
            if !tagName.isEmpty && !importer.staged[i].tagNames.contains(tagName) {
                importer.staged[i].tagNames.append(tagName)
            }
        }
        bulkTag = ""
    }
}
