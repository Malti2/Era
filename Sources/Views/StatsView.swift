import SwiftUI
import SwiftData
import Charts

// Listening Stats: fully local, built from PlayEvent history (no server).
struct StatsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \PlayEvent.date, order: .reverse) private var events: [PlayEvent]
    var showsDoneButton = true
    @State private var period: StatsCalculator.Period = .month

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
        let scoped = StatsCalculator.records(all, in: period)
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
                    let streak = StatsCalculator.currentStreak(all)
                    if streak > 1 {
                        LabeledContent("Current Streak", value: String(format: String(localized: "%lld days"), streak))
                    }
                }
                Section("Last 6 Months") {
                    activityChart(StatsCalculator.monthlySeries(all, months: 6))
                }
                Section {
                    Picker("Period", selection: $period) {
                        Text("Month").tag(StatsCalculator.Period.month)
                        Text("Year").tag(StatsCalculator.Period.year)
                        Text("All Time").tag(StatsCalculator.Period.allTime)
                    }
                    .pickerStyle(.segmented)
                    LabeledContent("Plays", value: "\(scoped.count)")
                    LabeledContent("Time Listened", value: TimeFormatting.spoken(scoped.reduce(0) { $0 + $1.seconds }))
                    LabeledContent("Listening Days", value: "\(StatsCalculator.activeDays(scoped))")
                    if !scoped.isEmpty {
                        LabeledContent("Per Listening Day", value: TimeFormatting.spoken(StatsCalculator.averageSecondsPerActiveDay(scoped)))
                    }
                }
                if !scoped.isEmpty { patternSection(scoped) }
                let tracks = StatsCalculator.topTracks(scoped, limit: 10)
                if !tracks.isEmpty {
                    Section("Top Tracks") {
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
                let artists = StatsCalculator.topArtists(scoped, limit: 5)
                if !artists.isEmpty {
                    Section("Top Artists") {
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

    private func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(.dateTime.hour())
    }

    private func weekdayName(at index: Int) -> String {
        let calendar = Calendar.current
        return calendar.weekdaySymbols[(calendar.firstWeekday - 1 + index) % 7]
    }

    private func patternSection(_ scoped: [PlayRecord]) -> some View {
        let hours = StatsCalculator.hourDistribution(scoped)
        let weekdays = StatsCalculator.weekdayDistribution(scoped)
        return Section("When You Listen") {
            Chart(Array(hours.enumerated()), id: \.offset) { hour, plays in
                BarMark(
                    x: .value(String(localized: "Hour"), hour),
                    y: .value(String(localized: "Plays"), plays)
                )
                .foregroundStyle(Color.accentColor.gradient)
            }
            .chartXScale(domain: -0.5...23.5)
            .chartXAxis { AxisMarks(values: [0, 6, 12, 18]) { value in
                AxisValueLabel { if let hour = value.as(Int.self) { Text(hourLabel(hour)) } }
            } }
            .chartYAxis(.hidden)
            .frame(height: 110)
            .padding(.vertical, 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("When You Listen"))
            if let peak = StatsCalculator.peakHour(scoped) {
                LabeledContent("Peak Hour", value: hourLabel(peak))
            }
            if let best = weekdays.max(), best > 0, let index = weekdays.firstIndex(of: best) {
                LabeledContent("Busiest Day", value: weekdayName(at: index))
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
