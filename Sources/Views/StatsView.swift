import SwiftUI
import SwiftData
import Charts

// Listening Stats: fully local, built from PlayEvent history (no server).
struct StatsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \PlayEvent.date, order: .reverse) private var events: [PlayEvent]
    @State private var range: StatsRange = .month
    var showsDoneButton = true

    var body: some View {
        let calc = StatsCalculator()
        let all = events.map { PlayRecord($0) }
        let scoped = calc.records(all, in: range)
        let buckets = calc.buckets(all, range: range)
        let tracks = calc.topTracks(scoped, limit: 5)
        let artists = calc.topArtists(scoped, limit: 5)
        let seconds = scoped.reduce(0) { $0 + $1.seconds }

        List {
            if events.isEmpty {
                ContentUnavailableView {
                    Label("No Plays Yet", systemImage: "chart.bar")
                } description: {
                    Text("Play music to see your listening stats.")
                }
            } else {
                Section {
                    Picker("Range", selection: $range) {
                        ForEach(StatsRange.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    HStack(spacing: 0) {
                        tile(value: "\(scoped.count)", label: String(localized: "Plays"))
                        tile(value: StatsCalculator.durationText(seconds), label: String(localized: "Time Listened"))
                        tile(value: "\(calc.currentStreak(all))", label: String(localized: "Day Streak"))
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 8, bottom: 12, trailing: 8))
                }
                if scoped.isEmpty {
                    Section {
                        Text("Nothing played in this period.").foregroundStyle(.secondary)
                    }
                } else {
                    Section("Activity") {
                        activityChart(buckets)
                            .frame(height: 160)
                            .padding(.vertical, 6)
                    }
                    if !tracks.isEmpty {
                        Section("Top Tracks") {
                            let top = tracks.first?.plays ?? 0
                            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                                rankRow(rank: index + 1, title: track.title, subtitle: track.artist,
                                        plays: track.plays, share: StatsCalculator.share(track.plays, of: top))
                            }
                        }
                    }
                    if !artists.isEmpty {
                        Section("Top Artists") {
                            let top = artists.first?.plays ?? 0
                            ForEach(Array(artists.enumerated()), id: \.element.id) { index, artist in
                                rankRow(rank: index + 1, title: artist.name.isEmpty ? String(localized: "Unknown Artist") : artist.name,
                                        subtitle: StatsCalculator.durationText(artist.seconds),
                                        plays: artist.plays, share: StatsCalculator.share(artist.plays, of: top))
                            }
                        }
                    }
                }
                Section("Records") {
                    LabeledContent("Longest Streak", value: String(localized: "\(calc.longestStreak(all)) days"))
                    LabeledContent("Active Days", value: "\(calc.activeDays(all).count)")
                    LabeledContent("Total Plays", value: "\(all.count)")
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

    private func tile(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.semibold).monospacedDigit()).minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func activityChart(_ buckets: [StatsBucket]) -> some View {
        let unit: Calendar.Component = (range == .week || range == .month) ? .day : .month
        return Chart(buckets) { bucket in
            BarMark(x: .value("Date", bucket.date, unit: unit),
                    y: .value("Minutes", bucket.seconds / 60))
                .foregroundStyle(Color.accentColor.gradient)
                .cornerRadius(3)
        }
        .chartYAxisLabel(String(localized: "min"), position: .top, alignment: .leading)
        .accessibilityLabel(Text("Listening activity"))
        .accessibilityValue(Text(String(localized: "\(buckets.reduce(0) { $0 + $1.plays }) plays")))
    }

    private func rankRow(rank: Int, title: String, subtitle: String, plays: Int, share: Double) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)").font(.headline).foregroundStyle(.secondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).lineLimit(1)
                if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                GeometryReader { geo in
                    Capsule().fill(Color.accentColor.opacity(0.35))
                        .frame(width: max(4, geo.size.width * share))
                }
                .frame(height: 4)
            }
            Spacer(minLength: 8)
            Text("\(plays)×").foregroundStyle(.secondary).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}
