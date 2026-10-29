import SwiftUI
import SwiftData
import Charts

// Listening Stats: fully local, built from PlayEvent history (no server).
struct StatsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \PlayEvent.date, order: .reverse) private var events: [PlayEvent]
    var showsDoneButton = true

    private var records: [PlayRecord] {
        events.map { PlayRecord(date: $0.date, seconds: $0.seconds, title: $0.title, artist: $0.artist) }
    }

    private func artistName(_ name: String) -> String {
        name.isEmpty ? String(localized: "Unknown Artist") : name
    }

    private func monthName(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }

    var body: some View {
        let all = records
        let month = StatsCalculator.records(all, inMonthOf: Date())
        List {
            if events.isEmpty {
                ContentUnavailableView {
                    Label("No Plays Yet", systemImage: "chart.bar")
                } description: {
                    Text("Play music to see your listening stats.")
                }
            } else {
                Section("All Time") {
                    LabeledContent("Plays", value: "\(all.count)")
                    LabeledContent("Time Listened", value: TimeFormatting.spoken(all.reduce(0) { $0 + $1.seconds }))
                    LabeledContent("Listening Days", value: "\(StatsCalculator.activeDays(all))")
                    let streak = StatsCalculator.currentStreak(all)
                    if streak > 1 {
                        LabeledContent("Current Streak", value: String(format: String(localized: "%lld days"), streak))
                    }
                }
                Section("Last 6 Months") {
                    activityChart(StatsCalculator.monthlySeries(all, months: 6))
                }
                Section("This Month") {
                    LabeledContent("Plays", value: "\(month.count)")
                    LabeledContent("Time Listened", value: TimeFormatting.spoken(month.reduce(0) { $0 + $1.seconds }))
                }
                let tracks = StatsCalculator.topTracks(month, limit: 5)
                if !tracks.isEmpty {
                    Section("Top Tracks This Month") {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            HStack {
                                Text("\(index + 1)")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(track.title).lineLimit(1)
                                    Text(artistName(track.artist)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Text("\(track.plays)×").foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                let artists = StatsCalculator.topArtists(month, limit: 3)
                if !artists.isEmpty {
                    Section("Top Artists This Month") {
                        ForEach(artists) { artist in
                            LabeledContent(artistName(artist.name), value: "\(artist.plays)×")
                        }
                    }
                }
                Section("By Month") {
                    ForEach(StatsCalculator.monthBuckets(all)) { bucket in
                        LabeledContent(monthName(bucket.month)) {
                            Text("\(bucket.plays) \(String(localized: "plays")) · \(TimeFormatting.spoken(bucket.seconds))")
                        }
                    }
                }
            }
        }
        .navigationTitle("Listening Stats")
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func activityChart(_ series: [StatsCalculator.MonthBucket]) -> some View {
        Chart(series) { bucket in
            BarMark(
                x: .value(String(localized: "Month"), bucket.month, unit: .month),
                y: .value(String(localized: "Plays"), bucket.plays)
            )
            .foregroundStyle(Color.accentColor.gradient)
            .cornerRadius(4)
        }
        .chartYAxis { AxisMarks(position: .leading) }
        .frame(height: 150)
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Last 6 Months"))
        .accessibilityValue(series.map { "\(monthName($0.month)): \($0.plays)" }.joined(separator: ", "))
    }
}
