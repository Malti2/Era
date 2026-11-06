import SwiftUI
import SwiftData

// Listet vermutliche Dubletten und fuehrt sie auf Wunsch als Versionen zusammen.
struct DuplicatesView: View {
    @EnvironmentObject private var store: EraStore
    @Query(sort: \Song.dateAdded) private var songs: [Song]
    @State private var pendingGroup: [Song]?

    private var groups: [[Song]] {
        let byID = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let items = songs.map { DuplicateFinder.Item(id: $0.id, title: $0.title, artist: $0.artist) }
        return DuplicateFinder.groups(items).map { ids in ids.compactMap { byID[$0] } }
    }

    var body: some View {
        let groups = groups
        List {
            if groups.isEmpty {
                ContentUnavailableView {
                    Label("No Duplicates", systemImage: "checkmark.circle")
                } description: {
                    Text("No songs with the same title and artist were found.")
                }
            } else {
                ForEach(groups.indices, id: \.self) { index in
                    let group = groups[index]
                    Section {
                        ForEach(group) { song in
                            SongRow(song: song, version: nil)
                        }
                        Button {
                            pendingGroup = group
                        } label: {
                            Label("Merge as Versions", systemImage: "arrow.triangle.merge")
                        }
                    } footer: {
                        if index == groups.count - 1 { Text("Merging keeps every audio file as a version of one song.") }
                    }
                }
            }
        }
        .navigationTitle("Find Duplicates")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Merge these songs?", isPresented: Binding(get: { pendingGroup != nil }, set: { if !$0 { pendingGroup = nil } }), titleVisibility: .visible) {
            Button("Merge as Versions") {
                if let group = pendingGroup { merge(group) }
                pendingGroup = nil
            }
            Button("Cancel", role: .cancel) { pendingGroup = nil }
        } message: {
            Text("Playlists and tags are kept.")
        }
    }

    /// The song with the most history survives; the others become its versions.
    private func merge(_ group: [Song]) {
        guard let target = group.max(by: { ($0.playCount, $0.versions.count) < ($1.playCount, $1.versions.count) }) else { return }
        for song in group where song.id != target.id {
            store.mergeSongAsVersions(song, into: target)
        }
    }
}
