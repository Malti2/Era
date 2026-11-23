import SwiftUI
import SwiftData
import Charts

// Jahresrueckblick: persoenliche Zusammenfassung eines Jahres aus der lokalen
// Hoerhistorie, mit teilbarer Karte. Alles bleibt auf dem Geraet.
struct YearReviewView: View {
    @Query(sort: \PlayEvent.date, order: .reverse) private var events: [PlayEvent]
    @Query private var songs: [Song]
    @State private var range: YearReviewRange?
    @State private var shareItem: ShareItem?
    @State private var showCustomRange = false
    @State private var customStart = Date()
    @State private var customEnd = Date()
    @State private var artistsShowTime = false
    @State private var tracksShowTime = false
    @State private var monthsShowTime = false

    private var records: [PlayRecord] {
        events.map { PlayRecord(date: $0.date, seconds: $0.seconds, title: $0.title, artist: $0.artist, songID: $0.songID) }
    }

    var body: some View {
        let all = records
        let years = YearReview.availableYears(all)
        let selectedRange = range ?? .year(years.first ?? Calendar.current.component(.year, from: Date()))
        let review = YearReview.make(range: selectedRange, from: all)
        let comparison: YearComparison? = {
            guard case .year(let selectedYear) = selectedRange else { return nil }
            return YearComparison.make(current: review, previous: YearReview.make(year: selectedYear - 1, from: all))
        }()
        let yearSelection = Binding<Int?>(
            get: { if case .year(let year) = range { year } else { nil } },
            set: { if let year = $0 { range = .year(year) } }
        )
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
                    if let comparison {
                        comparisonCard(comparison)
                    }
                    if !review.monthlySeries.isEmpty { monthSection(review.monthlySeries) }
                    if !review.topTracks.isEmpty {
                        rankedCard("Top Tracks",
                                   rows: (tracksShowTime ? review.topTracksByTime : review.topTracks)
                                    .map { ($0.title, artistName($0.artist), tracksShowTime ? TimeFormatting.spoken($0.seconds) : "\($0.plays)×") },
                                   timeToggle: $tracksShowTime)
                    }
                    if !review.topArtists.isEmpty {
                        rankedCard("Top Artists",
                                   rows: (artistsShowTime ? review.topArtistsByTime : review.topArtists)
                                    .map { (artistName($0.name), nil, artistsShowTime ? TimeFormatting.spoken($0.seconds) : "\($0.plays)×") },
                                   timeToggle: $artistsShowTime)
                    }
                    let albums = topAlbums(in: selectedRange, from: all)
                    if albums.count > 0 { rankedCard("Top Albums", rows: albums.map { ($0.name, nil, "\($0.plays)×") }) }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Year in Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !years.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Year", selection: yearSelection) {
                            ForEach(years, id: \.self) { Text(verbatim: String($0)).tag(Optional($0)) }
                        }
                        Section {
                            Button("Last 3 Months") { range = .trailing(months: 3) }
                            Button("Last 6 Months") { range = .trailing(months: 6) }
                            Button("Last 12 Months") { range = .trailing(months: 12) }
                            Button("All Time") { range = .allTime(from: all) }
                        }
                        Button("Custom Range…") { openCustomRange(selected: selectedRange) }
                    } label: { Label(selectedRange.title(), systemImage: "calendar") }
                }
            }
            if !years.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { share(review) } label: { Label("Share", systemImage: "square.and.arrow.up") }
                }
            }
        }
        .sheet(item: $shareItem) { ShareSheet(items: [$0.url]) }
        .sheet(isPresented: $showCustomRange) { customRangeSheet }
    }

    /// Eigene Spanne: zwei Datumswahlschalter, Tagesgrenzen, Ende nie vor dem Start.
    private var customRangeSheet: some View {
        NavigationStack {
            Form {
                DatePicker("Start Date", selection: $customStart, displayedComponents: .date)
                DatePicker("End Date", selection: $customEnd, displayedComponents: .date)
            }
            .navigationTitle("Custom Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showCustomRange = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let calendar = Calendar.current
                        let start = calendar.startOfDay(for: customStart)
                        let endDay = calendar.startOfDay(for: max(customEnd, customStart))
                        if let end = calendar.date(byAdding: .day, value: 1, to: endDay) {
                            range = .interval(DateInterval(start: start, end: end))
                        }
                        showCustomRange = false
                    }.fontWeight(.semibold)
                }
            }
        }
    }

    /// Vorbelegung der Datumswahl: aktuelle Spanne, sonst der letzte Monat.
    private func openCustomRange(selected: YearReviewRange) {
        if case .interval(let interval) = selected {
            customStart = interval.start
            customEnd = Calendar.current.date(byAdding: .day, value: -1, to: interval.end) ?? interval.start
        } else {
            customEnd = Date()
            customStart = Calendar.current.date(byAdding: .month, value: -1, to: customEnd) ?? customEnd
        }
        showCustomRange = true
    }

    /// Albums of the selected range by plays; songs without an album are left out.
    private func topAlbums(in selectedRange: YearReviewRange, from all: [PlayRecord]) -> [ListeningShare] {
        let inRange: [PlayRecord]
        switch selectedRange {
        case .year(let year):
            inRange = all.filter { Calendar.current.component(.year, from: $0.date) == year }
        case .interval(let interval):
            inRange = all.filter { $0.date >= interval.start && $0.date < interval.end }
        }
        let snapshot = Dictionary(songs.map { ($0.id, ListeningSong(album: $0.album)) }, uniquingKeysWith: { first, _ in first })
        return ListeningBreakdown.make(.album, records: inRange, songs: snapshot, limit: 6, unknownName: "")
            .filter { !$0.name.isEmpty }
            .sorted { $0.plays != $1.plays ? $0.plays > $1.plays : $0.seconds > $1.seconds }
            .prefix(5).map { $0 }
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

    private func comparisonCard(_ comparison: YearComparison) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Compared to \(String(comparison.previousYear))").font(.headline)
            HStack(alignment: .top, spacing: 12) {
                comparisonTile("Time Listened", comparison.secondsPercent.map(YearComparison.signedPercent)
                               ?? YearComparison.signed(Int((comparison.secondsDelta / 60).rounded())) + " min",
                               good: comparison.secondsDelta >= 0)
                comparisonTile("Plays", YearComparison.signed(comparison.playsDelta), good: comparison.playsDelta >= 0)
                comparisonTile("Active Days", YearComparison.signed(comparison.activeDaysDelta), good: comparison.activeDaysDelta >= 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func comparisonTile(_ title: LocalizedStringKey, _ value: String, good: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.bold().monospacedDigit()).foregroundStyle(good ? Color.green : Color.orange)
                .minimumScaleFactor(0.7).lineLimit(1)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
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

    private func monthSection(_ series: [StatsCalculator.MonthBucket]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Listening by Month").font(.headline)
                Spacer()
                Picker("Chart", selection: $monthsShowTime) {
                    Text("Plays").tag(false)
                    Text("Time").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }
            monthChart(series, showsTime: monthsShowTime)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func monthName(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated))
    }

    private func monthChart(_ series: [StatsCalculator.MonthBucket], showsTime: Bool) -> some View {
        Chart(series) { bucket in
            BarMark(
                x: .value(String(localized: "Month"), bucket.month, unit: .month),
                y: .value(String(localized: showsTime ? "Time Listened" : "Plays"),
                          showsTime ? bucket.seconds / 3600 : Double(bucket.plays))
            )
            .foregroundStyle(Color.accentColor.gradient)
            .cornerRadius(4)
        }
        .chartYAxis { AxisMarks(position: .leading) }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month, count: max(1, series.count / 6))) { value in
                AxisValueLabel { if let month = value.as(Date.self) { Text(monthName(month)) } }
            }
        }
        .frame(height: 150)
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Listening by Month"))
        .accessibilityValue(series.map { "\(monthName($0.month)): \(showsTime ? TimeFormatting.spoken($0.seconds) : "\($0.plays)")" }.joined(separator: ", "))
    }

    private func rankedCard(_ title: LocalizedStringKey, rows: [(String, String?, String)], timeToggle: Binding<Bool>? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if let timeToggle {
                    Picker("Sort", selection: timeToggle) {
                        Text("Plays").tag(false)
                        Text("Time").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 12) {
                    Text("\(index + 1)").font(.headline.monospacedDigit()).foregroundStyle(.secondary).frame(width: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.0).lineLimit(1)
                        if let subtitle = row.1 { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    Spacer()
                    Text(row.2).foregroundStyle(.secondary).monospacedDigit()
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
        let isYear: Bool = { if case .year = review.range { return true }; return false }()
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isYear ? "Year in Review" : "Listening Review").font(.subheadline.weight(.semibold)).opacity(0.8)
                if isYear {
                    Text(verbatim: String(review.year)).font(.system(size: 52, weight: .bold, design: .rounded))
                } else {
                    Text(review.range.title()).font(.system(size: 30, weight: .bold, design: .rounded))
                        .lineLimit(2).minimumScaleFactor(0.8)
                }
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
