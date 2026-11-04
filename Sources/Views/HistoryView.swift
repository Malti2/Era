import SwiftUI
import SwiftData

// Hoerverlauf: jede Wiedergabe nach Tagen gruppiert (gesamt oder fuer einen Song). Tippen spielt den Song erneut,
// Wischen loescht einzelne Eintraege. Basis ist dieselbe lokale PlayEvent-Historie wie in der Statistik.
struct HistoryView: View {
    var songID: UUID?
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var store: EraStore
    @EnvironmentObject private var player: PlayerEngine
    @Query private var events: [PlayEvent]
    @State private var query = ""
    @State private var confirmClear = false

    init(songID: UUID? = nil) {
        self.songID = songID
        if let songID {
            let id: UUID? = songID
            _events = Query(filter: #Predicate<PlayEvent> { $0.songID == id }, sort: \PlayEvent.date, order: .reverse)
        } else {
            _events = Query(sort: \PlayEvent.date, order: .reverse)
        }
    }

    private var entries: [HistoryEntry] {
        events.map { HistoryEntry(id: $0.id, date: $0.date, seconds: $0.seconds, title: $0.title, artist: $0.artist, songID: $0.songID) }
    }

    var body: some View {
        let days = PlayHistory.days(PlayHistory.filter(entries, query: query))
        List {
            if events.isEmpty {
                ContentUnavailableView {
                    Label("No Plays Yet", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("Every song you listen to shows up here.")
                }
                .listRowBackground(Color.clear)
            } else if days.isEmpty {
                ContentUnavailableView.search(text: query).listRowBackground(Color.clear)
            }
            ForEach(days) { day in
                Section {
                    ForEach(day.entries) { entry in
                        row(entry)
                    }
                    .onDelete { offsets in store.deletePlayEvents(ids: offsets.map { day.entries[$0].id }) }
                } header: {
                    header(day)
                }
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: Text("Search History"))
        .toolbar {
            if !events.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) { confirmClear = true } label: { Label("Clear History", systemImage: "trash") }
                    } label: { Label("More", systemImage: "ellipsis.circle") }
                }
            }
        }
        .confirmationDialog("Clear History?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear History", role: .destructive) { store.clearPlayHistory(songID: songID) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the listening history and its stats. Your songs are not affected.")
        }
    }

    @ViewBuilder private func header(_ day: HistoryDay) -> some View {
        HStack {
            Text(title(for: day.day))
            Spacer()
            Text("\(String(localized: "\(day.plays) plays")) · \(TimeFormatting.spoken(day.seconds))")
                .font(.caption)
                .textCase(nil)
        }
        .accessibilityElement(children: .combine)
    }

    private func title(for day: Date) -> String {
        switch PlayHistory.label(for: day) {
        case .today: String(localized: "Today")
        case .yesterday: String(localized: "Yesterday")
        case .date(let date): date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        }
    }

    private func row(_ entry: HistoryEntry) -> some View {
        let song = entry.songID.flatMap(findSong)
        return Button {
            if let version = song?.primaryVersion { player.play(version, from: [version]) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title).lineLimit(1)
                    Text(entry.artist.isEmpty ? String(localized: "Unknown Artist") : entry.artist)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(entry.date.formatted(date: .omitted, time: .shortened))
                    Text(TimeFormatting.mmss(entry.seconds))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(song == nil ? 0.5 : 1)
        .disabled(song?.primaryVersion == nil)
        .accessibilityElement(children: .combine)
        .accessibilityHint(song == nil ? "" : String(localized: "Plays this song again"))
    }

    private func findSong(_ id: UUID) -> Song? {
        var descriptor = FetchDescriptor<Song>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}
