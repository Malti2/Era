import SwiftUI
import SwiftData
import Charts

// Bibliotheks-Uebersicht: was ist in der Sammlung, in welchem Zustand (Status), aus welchen Eras, wie schnell waechst sie.
struct LibraryInsightsView: View {
    @Query private var songs: [Song]
    @State private var storageItems: [StorageItem] = []
    @State private var storage: StorageReport?

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
                if let storage, !storage.isEmpty { storageSections(storage) }
            }
        }
        .navigationTitle("Library Overview")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: songs.map { $0.versions.count }.reduce(0, +)) { await refreshStorage() }
    }

    private func refreshStorage() async {
        let items = await loadStorageItems()
        storageItems = items
        storage = StorageReport.make(from: items)
    }

    /// File sizes are read off the main thread; large libraries have thousands of files.
    private func loadStorageItems() async -> [StorageItem] {
        let snapshot = songs.flatMap { song in
            song.versions.map { (id: $0.id, songID: song.id, title: song.title, name: $0.name, file: $0.fileName,
                                 primary: song.primaryVersion?.id == $0.id, siblings: song.versions.count) }
        }
        return await Task.detached(priority: .utility) {
            let root = LibraryFiles.root
            return snapshot.map { entry -> StorageItem in
                let url = root.appendingPathComponent(entry.file)
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
                return StorageItem(id: entry.id, songID: entry.songID, title: entry.title, versionName: entry.name,
                                   fileExtension: url.pathExtension, bytes: size.map(Int64.init),
                                   isPrimary: entry.primary, siblingCount: entry.siblings)
            }
        }.value
    }

    private func sizeText(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    @ViewBuilder private func storageSections(_ report: StorageReport) -> some View {
        Section("Storage") {
            LabeledContent("Audio Files", value: sizeText(report.totalBytes))
            LabeledContent("Average File Size", value: sizeText(report.averageBytes))
            if report.missingCount > 0 {
                Label("\(report.missingCount) missing audio files", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            ForEach(report.formats) { format in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(format.name)
                        Spacer()
                        Text("\(format.count) · \(sizeText(format.bytes))").foregroundStyle(.secondary).monospacedDigit()
                    }
                    ProgressView(value: report.share(of: format.bytes)).tint(.accentColor)
                }
                .accessibilityElement(children: .combine)
            }
        }
        let cleanup = StorageCleanup.make(from: storageItems)
        if !cleanup.isEmpty {
            Section {
                NavigationLink {
                    StorageCleanupView(items: storageItems) { Task { await refreshStorage() } }
                } label: {
                    LabeledContent("Free Up Space", value: sizeText(cleanup.reclaimableBytes))
                }
            } footer: {
                Text("Alternate versions you could remove. Main versions are never touched.")
            }
        }
        if !report.largest.isEmpty {
            Section("Largest Files") {
                ForEach(report.largest) { item in
                    LabeledContent {
                        Text(sizeText(item.bytes ?? 0)).monospacedDigit()
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title).lineLimit(1)
                            Text(item.versionName).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
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
