import SwiftUI

// Details einer Version: Name, Jahr und Angaben, die vom Song abweichen (z.B. Demo-Titel).
struct VersionEditView: View {
    let version: SongVersion
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: EraStore
    @State private var name: String
    @State private var year: String
    @State private var title: String
    @State private var artist: String
    @State private var album: String
    @State private var yearInvalid = false

    init(version: SongVersion) {
        self.version = version
        _name = State(initialValue: version.name)
        _year = State(initialValue: version.year.map(String.init) ?? "")
        _title = State(initialValue: version.titleOverride ?? "")
        _artist = State(initialValue: version.artistOverride ?? "")
        _album = State(initialValue: version.albumOverride ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Version") {
                    TextField("Versionsname", text: $name)
                    TextField("Year", text: $year).keyboardType(.numberPad)
                    if yearInvalid {
                        Text("Enter a four-digit year or leave it empty.").font(.footnote).foregroundStyle(.red)
                    }
                }
                Section {
                    TextField("Title", text: $title, prompt: Text(version.song?.title ?? ""))
                    TextField("Artist", text: $artist, prompt: Text(version.song?.artist ?? ""))
                    TextField("Album", text: $album, prompt: Text(version.song?.album ?? ""))
                } header: {
                    Text("Different from the Song")
                } footer: {
                    Text("Leave a field empty to use the song’s value. Handy for demos with a working title.")
                }
            }
            .navigationTitle("Edit Version")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        if store.updateVersion(version, name: name, yearText: year, title: title, artist: artist, album: album) {
            dismiss()
        } else {
            yearInvalid = true
        }
    }
}
