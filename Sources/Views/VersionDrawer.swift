import SwiftUI
import SwiftData

// Drawer mit Segmented Picker: Importieren / Aus Bibliothek (Spec 4).
struct VersionDrawer: View {
    let song: Song
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: EraStore
    @EnvironmentObject private var importer: ImportManager
    @Query private var songs: [Song]

    @State private var mode = 0
    @State private var showFilePicker = false
    @State private var versionName = "OG"
    @State private var customName = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Quelle", selection: $mode) {
                    Text("Import").tag(0)
                    Text("From Library").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if mode == 0 { importPane } else { libraryPane }
            }
            .padding(.top)
            .navigationTitle("Version for “\(song.title)”")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            }
            .presentationDetents([.medium, .large])
            .sheet(isPresented: $showFilePicker) {
                DocumentPicker(contentTypes: ImportManager.importableTypes) { urls in
                    showFilePicker = false
                    guard !urls.isEmpty else { return }
                    Task {
                        await importer.importFiles(urls, into: store, linkTo: song, versionName: finalName)
                        dismiss()
                    }
                } onCancel: { showFilePicker = false }
            }
        }
    }

    private var finalName: String {
        customName.trimmingCharacters(in: .whitespaces).isEmpty ? versionName : customName.trimmingCharacters(in: .whitespaces)
    }

    private var importPane: some View {
        VStack(spacing: 18) {
            // Presets als Chips (Spec 4: OG, V2, Demo, Remaster, Live, Snippet, Released)
            VStack(alignment: .leading, spacing: 8) {
                Text("Versionsname").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(VersionPreset.all, id: \.self) { preset in
                            Button {
                                versionName = preset
                                customName = ""
                            } label: {
                                Text(preset)
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(versionName == preset && customName.isEmpty ? Color.accentColor : Color(.tertiarySystemFill), in: .capsule)
                                    .foregroundStyle(versionName == preset && customName.isEmpty ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                TextField("Custom Name", text: $customName)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal)

            Spacer()

            Button { showFilePicker = true } label: {
                Label("Choose File", systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .eraProminentButton()
            .controlSize(.large)
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    private var libraryPane: some View {
        List(songs.filter { $0.id != song.id }) { other in
            Button {
                link(other)
            } label: {
                HStack(spacing: 12) {
                    Artwork(song: other, radius: 7).frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(other.title).lineLimit(1)
                        Text(other.displayArtist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "link").foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.plain)
    }

    // Song aus der Bibliothek einhaengen: Alle Versionen wandern unter den
    // Ziel-Song; der Quell-Song ist danach kein eigener Library-Eintrag mehr.
    private func link(_ other: Song) {
        store.mergeSongAsVersions(other, into: song)
        dismiss()
    }
}
