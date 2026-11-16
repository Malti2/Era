import SwiftUI

// Album-Reihenfolge per Ziehen festlegen; beim Sichern bekommen die Songs die Nummern 1...n.
struct TrackOrderView: View {
    let songs: [Song]
    @EnvironmentObject private var store: EraStore
    @Environment(\.dismiss) private var dismiss
    @State private var order: [Song]

    init(songs: [Song]) {
        self.songs = songs
        _order = State(initialValue: songs)
    }

    private var isChanged: Bool { order.map(\.id) != songs.map(\.id) || order.contains { $0.trackNumber == 0 } }

    /// Angezeigte neue Nummern: je Disc neu bei 1 ("2·3" = Disc 2, Track 3), sonst global 1...n.
    /// Spiegelt `EraStore.applyTrackOrder`, damit die Vorschau stimmt.
    private var numberLabels: [String] {
        let hasDiscs = order.contains { $0.discNumber > 0 }
        var perDisc: [Int: Int] = [:]
        return order.enumerated().map { index, song in
            guard hasDiscs else { return "\(index + 1)" }
            perDisc[song.discNumber, default: 0] += 1
            let number = perDisc[song.discNumber] ?? 1
            return song.discNumber > 0 ? "\(song.discNumber)·\(number)" : "\(number)"
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(order.enumerated()), id: \.element.id) { index, song in
                        HStack(spacing: 12) {
                            Text(numberLabels[index])
                                .font(.body.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 28, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title).lineLimit(1)
                                if let version = song.primaryVersion {
                                    Text(version.durationText).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .onMove { order.move(fromOffsets: $0, toOffset: $1) }
                } footer: {
                    Text("Drag songs into album order. Numbers are stored in Era only; your files stay untouched.")
                }
                if songs.contains(where: { $0.trackNumber != 0 }) {
                    Section {
                        Button(role: .destructive) {
                            store.clearTrackNumbers(of: songs)
                            dismiss()
                        } label: { Label("Remove Track Numbers", systemImage: "number.circle") }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Track Order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { store.applyTrackOrder(order); dismiss() }
                        .fontWeight(.semibold)
                        .disabled(!isChanged)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
