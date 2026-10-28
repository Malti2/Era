import SwiftUI
import SwiftData

// Metadaten editierbar (Spec 8): Titel, Artist, Album, Jahr, Era, Status, Tags.
// Stored in Era (SwiftData), non-destructive to the file.
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
    // Tag edits stay in a draft until "Sichern", so Cancel really discards them.
    @State private var tagIDs: Set<UUID> = []
    @State private var pendingTagNames: [String] = []

    init(song: Song) {
        self.song = song
        _title = State(initialValue: song.title)
        _artist = State(initialValue: song.artist)
        _album = State(initialValue: song.album)
        _era = State(initialValue: song.era)
        _year = State(initialValue: song.year.map(String.init) ?? "")
        _tagIDs = State(initialValue: Set(song.tags.map(\.id)))
    }

    private var statusTags: [Tag] { tags.filter { $0.isStatus } }
    private var draftPersonalTags: [Tag] {
        tags.filter { !$0.isStatus && tagIDs.contains($0.id) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private var trimmedNewTag: String { newTag.trimmingCharacters(in: .whitespacesAndNewlines) }

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
                                if tagIDs.contains(tag.id) {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }
                Section("Tags") {
                    ForEach(draftPersonalTags) { tag in
                        tagRow(tag.name) { tagIDs.remove(tag.id) }
                    }
                    ForEach(pendingTagNames, id: \.self) { name in
                        tagRow(name) { pendingTagNames.removeAll { $0 == name } }
                    }
                    HStack {
                        TextField("New Tag", text: $newTag).onSubmit(addTag)
                        Button(action: addTag) { Image(systemName: "plus.circle.fill") }
                            .disabled(trimmedNewTag.isEmpty)
                            .accessibilityLabel("Add Tag")
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

    private func tagRow(_ name: String, remove: @escaping () -> Void) -> some View {
        HStack {
            Text(name)
            Spacer()
            Button(role: .destructive, action: remove) {
                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Remove \(name)"))
        }
    }

    private func addTag() {
        let name = trimmedNewTag
        guard !name.isEmpty else { return }
        defer { newTag = "" }
        // Existing tag (any case) -> select it, otherwise it is created on save.
        if let existing = tags.first(where: { !$0.isStatus && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            tagIDs.insert(existing.id)
        } else if !pendingTagNames.contains(where: { $0.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            pendingTagNames.append(name)
        }
    }

    private func toggle(_ tag: Tag) {
        if tagIDs.contains(tag.id) { tagIDs.remove(tag.id) } else { tagIDs.insert(tag.id) }
    }

    private func save() {
        song.title = title.trimmingCharacters(in: .whitespaces).isEmpty ? song.title : title.trimmingCharacters(in: .whitespaces)
        song.artist = artist.trimmingCharacters(in: .whitespaces)
        song.album = album.trimmingCharacters(in: .whitespaces)
        song.era = era.trimmingCharacters(in: .whitespaces)
        song.year = Int(year.trimmingCharacters(in: .whitespaces))
        var final = tags.filter { tagIDs.contains($0.id) }
        for name in pendingTagNames {
            let tag = store.makeTag(named: name)
            if !final.contains(where: { $0.id == tag.id }) { final.append(tag) }
        }
        song.tags = final
        store.save()
    }
}
