import SwiftUI

// Freie Notiz am Song (Ideen, Session-Infos, Herkunft). Bleibt bis "Sichern" ein Entwurf.
struct SongNotesView: View {
    let song: Song
    @EnvironmentObject private var store: EraStore
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @FocusState private var focused: Bool

    init(song: Song) {
        self.song = song
        _text = State(initialValue: song.notes)
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .focused($focused)
                .padding(.horizontal, 12)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Ideas, session details, where this came from…")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 17).padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
                .navigationTitle("Notes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") { store.setNotes(text, for: song); dismiss() }.fontWeight(.semibold)
                    }
                }
                .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }
}
