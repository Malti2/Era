import SwiftUI
import SwiftData

// Jahresrueckblick: persoenliche Zusammenfassung eines Jahres aus der lokalen
// Hoerhistorie, mit teilbarer Karte. Alles bleibt auf dem Geraet.
struct YearReviewView: View {
    @Query(sort: \PlayEvent.date, order: .reverse) private var events: [PlayEvent]
    @State private var year: Int?
    @State private var shareItem: ShareItem?

    private var records: [PlayRecord] {
        events.map { PlayRecord(date: $0.date, seconds: $0.seconds, title: $0.title, artist: $0.artist) }
    }

    var body: some View {
        let all = records
        let years = YearReview.availableYears(all)
        let selected = year ?? years.first ?? Calendar.current.component(.year, from: Date())
        let review = YearReview.make(year: selected, from: all)
        ScrollView {
            VStack(spacing: 18) {
                if years.isEmpty {
                    ContentUnavailableView {
                        Label("No Plays Yet", systemImage: "chart.bar")
                    } description: {
                        Text("Play music to see your listening stats.")
                    }
                } else {
                    YearReviewCard(review: review)
                    highlights(review)
                    if !review.topTracks.isEmpty { rankedCard("Top Tracks", rows: review.topTracks.map { ($0.title, artistName($0.artist), $0.plays) }) }
                    if !review.topArtists.isEmpty { rankedCard("Top Artists", rows: review.topArtists.map { (artistName($0.name), nil, $0.plays) }) }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Year in Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if years.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Year", selection: Binding(get: { selected }, set: { year = $0 })) {
                            ForEach(years, id: \.self) { Text(verbatim: String($0)).tag($0) }
                        }
                    } label: { Label(String(selected), systemImage: "calendar") }
                }
            }
            if !years.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { share(review) } label: { Label("Share", systemImage: "square.and.arrow.up") }
                }
            }
        }
        .sheet(item: $shareItem) { ShareSheet(items: [$0.url]) }
    }

    private func artistName(_ name: String) -> String {
        name.isEmpty ? String(localized: "Unknown Artist") : name
    }

    @MainActor private func share(_ review: YearReview) {
        let renderer = ImageRenderer(content: YearReviewCard(review: review).frame(width: 360))
        renderer.scale = 3
        guard let data = renderer.uiImage?.pngData() else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Era-\(review.year)-in-Review.png")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        shareItem = ShareItem(url: url)
    }

    private func highlights(_ review: YearReview) -> some View {
        VStack(spacing: 0) {
            let rows = highlightRows(review)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Divider().padding(.leading, 52) }
                HStack(spacing: 14) {
                    Image(systemName: row.icon).font(.title3).foregroundStyle(.tint).frame(width: 26)
                    Text(row.title)
                    Spacer()
                    Text(row.value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .accessibilityElement(children: .combine)
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private struct HighlightRow {
        let icon: String
        let title: LocalizedStringKey
        let value: String
    }

    private func highlightRows(_ review: YearReview) -> [HighlightRow] {
        var rows: [HighlightRow] = []
        if let month = review.busiestMonth {
            rows.append(HighlightRow(icon: "calendar", title: "Busiest Month", value: month.month.formatted(.dateTime.month(.wide))))
        }
        if let index = review.busiestWeekdayIndex {
            let calendar = Calendar.current
            rows.append(HighlightRow(icon: "sun.max", title: "Busiest Day", value: calendar.weekdaySymbols[(calendar.firstWeekday - 1 + index) % 7]))
        }
        if let hour = review.peakHour {
            let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
            rows.append(HighlightRow(icon: "clock", title: "Peak Hour", value: date.formatted(.dateTime.hour())))
        }
        if review.longestStreak > 1 {
            rows.append(HighlightRow(icon: "flame", title: "Longest Streak", value: String(localized: "\(review.longestStreak) days")))
        }
        if review.newTracks > 0 {
            rows.append(HighlightRow(icon: "sparkles", title: "New Tracks", value: "\(review.newTracks)"))
        }
        return rows
    }

    private func rankedCard(_ title: LocalizedStringKey, rows: [(String, String?, Int)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 12) {
                    Text("\(index + 1)").font(.headline.monospacedDigit()).foregroundStyle(.secondary).frame(width: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.0).lineLimit(1)
                        if let subtitle = row.1 { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    Spacer()
                    Text("\(row.2)×").foregroundStyle(.secondary).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Die teilbare Karte. Eigene feste Farben, damit sie in Light/Dark und im gerenderten Bild gleich aussieht.
struct YearReviewCard: View {
    let review: YearReview

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Year in Review").font(.subheadline.weight(.semibold)).opacity(0.8)
                Text(verbatim: String(review.year)).font(.system(size: 52, weight: .bold, design: .rounded))
            }
            HStack(alignment: .top, spacing: 24) {
                stat(value: TimeFormatting.spoken(review.seconds), caption: "Time Listened")
                stat(value: "\(review.plays)", caption: "Plays")
                stat(value: "\(review.activeDays)", caption: "Listening Days")
            }
            if let track = review.topTracks.first {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Top Track").font(.caption.weight(.semibold)).opacity(0.75)
                    Text(track.title).font(.title3.weight(.semibold)).lineLimit(2)
                    if !track.artist.isEmpty { Text(track.artist).font(.subheadline).opacity(0.85).lineLimit(1) }
                }
            }
            if let artist = review.topArtists.first, !artist.name.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Top Artist").font(.caption.weight(.semibold)).opacity(0.75)
                    Text(artist.name).font(.title3.weight(.semibold)).lineLimit(1)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "opticaldisc")
                Text("Era").fontWeight(.semibold)
            }
            .font(.footnote).opacity(0.8)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(
            LinearGradient(colors: [Color(red: 0.36, green: 0.25, blue: 0.80), Color(red: 0.84, green: 0.27, blue: 0.52)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func stat(value: String, caption: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.bold().monospacedDigit()).minimumScaleFactor(0.7).lineLimit(1)
            Text(caption).font(.caption).opacity(0.8)
        }
    }
}
