import SwiftUI
import SwiftData

// Natural-language playlist creation via Apple Intelligence.
// Only reachable on devices where IntelligenceService.isAvailable is true
// (plus the screenshot demo flag); anything else shows the plain unavailable state.
struct SmartPlaylistView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: EraStore
    @Query(sort: \Song.dateAdded, order: .reverse) private var songs: [Song]

    @State private var prompt = ""
    @State private var isWorking = false
    @State private var error: String?
    @State private var suggestionName = ""
    @State private var matched: [Song] = []
    @State private var excluded: Set<UUID> = []
    @State private var editingPrompt = false

    private var hasResult: Bool { !matched.isEmpty }
    private var included: [Song] { matched.filter { !excluded.contains($0.id) } }
    private let examples = ["Late night drive", "Unreleased favorites", "Calm acoustic demos"]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Late night drive, dark and slow…", text: $prompt, axis: .vertical)
                        .lineLimit(2...4)
                        .disabled(isWorking)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack { ForEach(examples, id: \.self) { example in Button(example) { prompt = example }.buttonStyle(.bordered).controlSize(.small) } }
                    }
                } header: {
                    Text("Describe the playlist")
                } footer: {
                    Text("Apple Intelligence picks matching songs from your library. Everything stays on this iPhone.")
                }

                if isWorking {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Thinking…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                if hasResult {
                    Section {
                        TextField("Playlist Name", text: $suggestionName)
                        ForEach(matched) { song in
                            Button {
                                if excluded.contains(song.id) { excluded.remove(song.id) } else { excluded.insert(song.id) }
                            } label: {
                                HStack {
                                    SongRow(song: song, version: nil)
                                    Image(systemName: excluded.contains(song.id) ? "circle" : "checkmark.circle.fill")
                                        .foregroundStyle(excluded.contains(song.id) ? .secondary : Color.accentColor)
                                }
                            }.buttonStyle(.plain)
                        }
                        Button("Generate Again", systemImage: "arrow.clockwise") { generate() }
                        Button("Edit Description", systemImage: "pencil") { matched = []; excluded = [] }

                    } header: {
                        Text("\(included.count) songs")
                    }
                }
            }
            .navigationTitle("Smart Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if hasResult {
                        Button("Create") {
                            createPlaylist()
                            dismiss()
                        }
                        .fontWeight(.semibold)
                        .disabled(suggestionName.trimmingCharacters(in: .whitespaces).isEmpty || included.isEmpty)
                    } else {
                        Button("Generate") { generate() }
                            .fontWeight(.semibold)
                            .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func generate() {
        let request = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }
        error = nil
        matched = []
        excluded = []
        guard IntelligenceService.isAvailable else {
            error = String(localized: "Apple Intelligence is not available on this device.")
            return
        }
        isWorking = true
        let descriptors = songs.map {
            IntelligenceService.SongDescriptor(
                id: $0.id, title: $0.title, artist: $0.artist, album: $0.album,
                tags: $0.tags.map(\.name))
        }
        Task {
            defer { isWorking = false }
            do {
                #if canImport(FoundationModels)
                if #available(iOS 26.0, macOS 26.0, *) {
                    let result = try await IntelligenceService.suggestPlaylist(prompt: request, songs: descriptors)
                    suggestionName = result.name
                    matched = songs.filter { result.ids.contains($0.id) }
                        .sorted { a, b in
                            (result.ids.firstIndex(of: a.id) ?? 0) < (result.ids.firstIndex(of: b.id) ?? 0)
                        }
                }
                #endif
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func createPlaylist() {
        let name = suggestionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let playlist = Playlist(name: name.isEmpty ? String(localized: "Smart Playlist") : name)
        store.insertPlaylist(playlist)
        for song in included {
            store.appendEntry(song: song, version: song.primaryVersion, to: playlist)
        }
    }
}
