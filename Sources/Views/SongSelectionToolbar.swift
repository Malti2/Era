import SwiftUI

// Untere Leiste der Mehrfachauswahl, gemeinsam fuer Bibliothek und Album-/Kuenstler-Details.
struct SongSelectionToolbar: ToolbarContent {
    let chosen: [Song]
    let store: EraStore
    let playlistPicker: PlaylistPickerCoordinator
    @Binding var showTags: Bool
    @Binding var confirmDelete: Bool

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            let allFavorites = !chosen.isEmpty && chosen.allSatisfy(\.isFavorite)
            Button { playlistPicker.present(chosen) } label: { Label("Add to Playlist", systemImage: "text.badge.plus") }
                .disabled(chosen.isEmpty)
            Spacer()
            Button { store.setFavorite(!allFavorites, for: chosen) } label: {
                Label(LocalizedStringKey(allFavorites ? "Remove Favorite" : "Favorite"), systemImage: allFavorites ? "heart.slash" : "heart")
            }
            .disabled(chosen.isEmpty)
            Spacer()
            Button { showTags = true } label: { Label("Tags", systemImage: "tag") }
                .disabled(chosen.isEmpty)
            Spacer()
            Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                .disabled(chosen.isEmpty)
        }
    }
}

// Zeile mit Auswahlkreis fuer den Auswahlmodus.
struct SelectableSongRow: View {
    let song: Song
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                SongRow(song: song, version: nil, isCurrent: false)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
