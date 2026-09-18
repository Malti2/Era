import SwiftUI
import SwiftData

// Metadaten editierbar (Spec 8): Titel, Artist, Album, Jahr, Era, Status, Tags.
// Gespeichert in Era (SwiftData), nicht destruktiv an der Datei (siehe DECISIONS.md).
struct MetadataEditView: View {
    let song: Song
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: EraStore
    @Query private var tags: [Tag]

    @State private var title: String = ""
    @State private var artist: String = ""
    @State private var album: String = ""
    @State private var era: String = ""
    @State private var year: String = ""
    @State private var newTag = ""

    init(song: Song) {
        self.song = song
        _title = State(initialValue: song.title)
        _artist = State(initialValue: song.artist)
        _album = State(initialValue: song.album)
        _era = State(initialValue: song.era)
        _year = State(initialValue: song.year.map(String.init) ?? "")
    }

    private var statusTags: [Tag] { tags.filter { $0.isStatus } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Song") {
                    TextField("Title", text: $title)
                    TextField("Artist", text: $artist)
                    TextField("Album", text: $album)
                    TextField("Era / Project", text: $era)
                    TextField("Year", text: $year).keyboardType(.numberPad)
                }
                Section("Status") {
                    ForEach(statusTags) { tag in
                        Button { toggle(tag) } label: {
                            HStack {
                                Text(tag.name).foregroundStyle(.primary)
                                Spacer()
                                if song.tags.contains(where: { $0.id == tag.id }) {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }
                Section("Tags") {
                    ForEach(song.personalTags) { tag in
                        HStack {
                            Text(tag.name)
                            Spacer()
                            Button(role: .destructive) { song.tags.removeAll { $0.id == tag.id } } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack {
                        TextField("New Tag", text: $newTag)
                        Button {
                            let name = newTag.trimmingCharacters(in: .whitespaces)
                            guard !name.isEmpty else { return }
                            let tag = store.makeTag(named: name)
                            if !song.tags.contains(where: { $0.id == tag.id }) { song.tags.append(tag) }
                            newTag = ""
                        } label: { Image(systemName: "plus.circle.fill") }
                        .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle("Metadaten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sichern") { save(); dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }

    private func toggle(_ tag: Tag) {
        if song.tags.contains(where: { $0.id == tag.id }) {
            song.tags.removeAll { $0.id == tag.id }
        } else {
            song.tags.append(tag)
        }
    }

    private func save() {
        song.title = title.trimmingCharacters(in: .whitespaces).isEmpty ? song.title : title.trimmingCharacters(in: .whitespaces)
        song.artist = artist.trimmingCharacters(in: .whitespaces)
        song.album = album.trimmingCharacters(in: .whitespaces)
        song.era = era.trimmingCharacters(in: .whitespaces)
        song.year = Int(year)
        store.save()
    }
}
