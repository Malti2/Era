import SwiftUI
import SwiftData
import Charts

// Bibliotheks-Uebersicht: was ist in der Sammlung, in welchem Zustand (Status), aus welchen Eras, wie schnell waechst sie.
struct LibraryInsightsView: View {
    @Query private var songs: [Song]

    private var insights: LibraryInsights {
        LibraryInsights.make(from: songs.map { song in
            InsightSong(statuses: song.statusTags.map(\.name), era: song.era, dateAdded: song.dateAdded,
                        versionCount: song.versions.count, duration: song.duration, playCount: song.playCount,
                        isFavorite: song.isFavorite, hasNotes: !song.notes.isEmpty,
                        markerCount: song.versions.reduce(0) { $0 + $1.markers.count })
        }, unknownName: String(localized: "Unknown"))
    }

    var body: some View {
        let insights = insights
        List {
            if insights.isEmpty {
                ContentUnavailableView {
                    Label("Your Library Is Empty", systemImage: "music.note.list")
                } description: {
                    Text("Import songs from the Files app to build your library.")
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    LabeledContent("Songs", value: "\(insights.songs)")
                    LabeledContent("Versions", value: "\(insights.versions)")
                    LabeledContent("Total Duration", value: TimeFormatting.spoken(insights.totalSeconds))
                    LabeledContent("Versions per Song", value: insights.averageVersions.formatted(.number.precision(.fractionLength(1))))
                }
                Section {
                    LabeledContent("Favorites", value: "\(insights.favorites)")
                    LabeledContent("Not Played Yet", value: "\(insights.neverPlayed)")
                    LabeledContent("Songs with Notes", value: "\(insights.withNotes)")
                    LabeledContent("Markers", value: "\(insights.markers)")
                }
                if !insights.statuses.isEmpty { statusSection(insights) }
                if !insights.eras.isEmpty {
                    Section("Top Eras") {
                        ForEach(insights.eras) { era in LabeledContent(era.name, value: "\(era.count)") }
                    }
                }
                if insights.addedPerYear.count > 1 { growthSection(insights) }
            }
        }
        .navigationTitle("Library Overview")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statusSection(_ insights: LibraryInsights) -> some View {
        Section("By Status") {
            Chart(insights.statuses) { entry in
                BarMark(x: .value(String(localized: "Songs"), entry.count), y: .value(String(localized: "Status"), entry.name))
                    .foregroundStyle(Color.accentColor.gradient)
                    .cornerRadius(4)
                    .annotation(position: .trailing) { Text("\(entry.count)").font(.caption).foregroundStyle(.secondary) }
            }
            .chartXAxis(.hidden)
            .frame(height: CGFloat(insights.statuses.count) * 30 + 12)
            .padding(.vertical, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("By Status"))
            .accessibilityValue(insights.statuses.map { "\($0.name): \($0.count)" }.joined(separator: ", "))
        }
    }

    private func growthSection(_ insights: LibraryInsights) -> some View {
        Section("Added per Year") {
            Chart(insights.addedPerYear) { entry in
                BarMark(x: .value(String(localized: "Year"), String(entry.year)), y: .value(String(localized: "Songs"), entry.count))
                    .foregroundStyle(Color.accentColor.gradient)
                    .cornerRadius(4)
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 140)
            .padding(.vertical, 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Added per Year"))
            .accessibilityValue(insights.addedPerYear.map { "\($0.year): \($0.count)" }.joined(separator: ", "))
        }
    }
}
