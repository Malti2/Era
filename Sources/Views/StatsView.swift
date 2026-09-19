import SwiftUI
import SwiftData

// Listening Stats: fully local, built from PlayEvent history (no server).
struct StatsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \PlayEvent.date, order: .reverse) private var events: [PlayEvent]
    var showsDoneButton = true

    private struct MonthBucket: Identifiable {
        let id: Date
        let month: Date
        var plays: Int
        var seconds: Double
    }

    private var calendar: Calendar { Calendar.current }

    private func monthStart(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private var buckets: [MonthBucket] {
        var map: [Date: MonthBucket] = [:]
        for event in events {
            let key = monthStart(event.date)
            var bucket = map[key] ?? MonthBucket(id: key, month: key, plays: 0, seconds: 0)
            bucket.plays += 1
            bucket.seconds += event.seconds
            map[key] = bucket
        }
        return map.values.sorted { $0.month > $1.month }
    }

    private var thisMonth: [PlayEvent] {
        let start = monthStart(Date())
        return events.filter { $0.date >= start }
    }

    private func topTracks(in scope: [PlayEvent], limit: Int) -> [(String, String, Int)] {
        var map: [String: (String, String, Int)] = [:]
        for event in scope {
            let key = "\(event.title)\u{1F}\(event.artist)"
            let entry = map[key] ?? (event.title, event.artist, 0)
            map[key] = (entry.0, entry.1, entry.2 + 1)
        }
        return Array(map.values.sorted { lhs, rhs in
            if lhs.2 != rhs.2 { return lhs.2 > rhs.2 }
            let titleOrder = lhs.0.localizedCaseInsensitiveCompare(rhs.0)
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            return lhs.1.localizedCaseInsensitiveCompare(rhs.1) == .orderedAscending
        }.prefix(limit))
    }

    private func topArtists(in scope: [PlayEvent], limit: Int) -> [(String, Int)] {
        var map: [String: Int] = [:]
        for event in scope { map[event.artist, default: 0] += 1 }
        return map.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
        }.prefix(limit).map { ($0.key, $0.value) }
    }

    private func durationText(_ seconds: Double) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours) h \(minutes) min" }
        return "\(minutes) min"
    }

    private func monthName(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }

    var body: some View {
            List {
                if events.isEmpty {
                    ContentUnavailableView {
                        Label("No Plays Yet", systemImage: "chart.bar")
                    } description: {
                        Text("Play music to see your listening stats.")
                    }
                } else {
                    Section("This Month") {
                        LabeledContent("Plays", value: "\(thisMonth.count)")
                        LabeledContent("Time Listened", value: durationText(thisMonth.reduce(0) { $0 + $1.seconds }))
                    }
                    let monthTracks = topTracks(in: thisMonth, limit: 5)
                    if !monthTracks.isEmpty {
                        Section("Top Tracks This Month") {
                            ForEach(Array(monthTracks.enumerated()), id: \.element.0) { index, track in
                                HStack {
                                    Text("\(index + 1)")
                                        .font(.headline)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(track.0).lineLimit(1)
                                        Text(track.1).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Text("\(track.2)×").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    let monthArtists = topArtists(in: thisMonth, limit: 3)
                    if !monthArtists.isEmpty {
                        Section("Top Artists This Month") {
                            ForEach(monthArtists, id: \.0) { artist, count in
                                LabeledContent(artist, value: "\(count)×")
                            }
                        }
                    }
                    Section("By Month") {
                        ForEach(buckets) { bucket in
                            LabeledContent(monthName(bucket.month)) {
                                Text("\(bucket.plays) \(String(localized: "plays")) · \(durationText(bucket.seconds))")
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
}
