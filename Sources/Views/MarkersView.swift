import SwiftUI

// Marker einer Version als Liste: antippen springt hin, Wischen loescht, Halten benennt um.
struct MarkersSheet: View {
    let version: SongVersion
    let onSelect: (VersionMarker) -> Void
    @EnvironmentObject private var store: EraStore
    @Environment(\.dismiss) private var dismiss
    @State private var markerToRename: VersionMarker?
    @State private var renameText = ""
    @State private var shareText: MarkerShareText?

    var body: some View {
        NavigationStack {
            Group {
                let markers = version.markers
                if markers.isEmpty {
                    ContentUnavailableView("No Markers", systemImage: "mappin.slash",
                                           description: Text("Set markers while listening to find your way back to the good parts."))
                } else {
                    List {
                        ForEach(markers) { marker in
                            Button {
                                onSelect(marker)
                                dismiss()
                            } label: { MarkerRow(marker: marker) }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button(role: .destructive) { store.removeMarker(marker.id, from: version) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button { beginRename(marker) } label: { Label("Rename", systemImage: "pencil") }
                                Button(role: .destructive) { store.removeMarker(marker.id, from: version) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Markers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !version.markers.isEmpty {
                        Button { shareText = MarkerShareText(text: shareBody) } label: { Label("Share Markers", systemImage: "square.and.arrow.up") }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !copySources.isEmpty {
                        Menu {
                            ForEach(copySources) { source in
                                Button { _ = store.copyMarkers(from: source, to: version) } label: {
                                    Label(copySourceLabel(source), systemImage: "mappin")
                                }
                            }
                        } label: { Label("Copy Markers", systemImage: "square.on.square") }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.fontWeight(.semibold) }
            }
            .sheet(item: $shareText) { ShareSheet(items: [$0.text]) }
            .alert("Rename Marker", isPresented: Binding(get: { markerToRename != nil }, set: { if !$0 { markerToRename = nil } })) {
                TextField("Name", text: $renameText)
                Button("Save") {
                    if let marker = markerToRename { store.renameMarker(marker.id, to: renameText, in: version) }
                    markerToRename = nil
                }
                Button("Cancel", role: .cancel) { markerToRename = nil }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var shareBody: String {
        let title = [version.displayTitle, version.name].filter { !$0.isEmpty }.joined(separator: " · ")
        return title + "\n" + VersionMarkers.listText(version.markers)
    }

    /// Andere Versionen desselben Songs, die Marker haben - als Quelle zum Kopieren.
    private var copySources: [SongVersion] {
        guard let song = version.song else { return [] }
        return song.sortedVersions.filter { $0.id != version.id && !$0.markers.isEmpty }
    }

    private func copySourceLabel(_ source: SongVersion) -> String {
        let name = source.name.isEmpty ? "OG" : source.name
        if let year = source.year { return "\(name) (\(year))" }
        return name
    }

    private func beginRename(_ marker: VersionMarker) {
        renameText = marker.label
        markerToRename = marker
    }
}

private struct MarkerShareText: Identifiable {
    let text: String
    var id: String { text }
}

/// "Name, mm:ss" – ein Label fuer Marker, in Liste und Scrubber gleich.
private func markerAccessibilityLabel(_ marker: VersionMarker) -> String {
    let name = marker.label.isEmpty ? String(localized: "Marker") : marker.label
    return "\(name), \(TimeFormatting.mmss(marker.time))"
}

struct MarkerRow: View {
    let marker: VersionMarker

    var body: some View {
        HStack(spacing: 12) {
            Text(TimeFormatting.mmss(marker.time))
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(minWidth: 48, alignment: .leading)
            Text(marker.label.isEmpty ? String(localized: "Marker") : marker.label)
                .foregroundStyle(marker.label.isEmpty ? .secondary : .primary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(markerAccessibilityLabel(marker))
    }
}

/// Dezente Skala unter dem Scrubber: Marker als kleine Striche, aktive A-B-Schleife als Band.
/// Die Striche sind tippbar (springen zum Marker) und haben eine VoiceOver-Beschreibung.
struct ScrubberOverlay: View {
    let markers: [VersionMarker]
    let loopStart: Double?
    let loopEnd: Double?
    let duration: Double
    var onMarkerTap: ((VersionMarker) -> Void)? = nil

    // Slider-Daumen sitzt innen: Skala entsprechend einruecken.
    private let inset: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width - inset * 2)
            let y = geo.size.height - 3
            ZStack(alignment: .topLeading) {
                if let start = loopStart {
                    let endX = loopEnd.map { x($0, width) } ?? x(start, width)
                    Capsule().fill(Color.accentColor.opacity(0.9))
                        .frame(width: max(3, endX - x(start, width)), height: 3)
                        .position(x: x(start, width) + max(3, endX - x(start, width)) / 2, y: y)
                        .accessibilityHidden(true)
                }
                ForEach(markers) { marker in
                    Button { onMarkerTap?(marker) } label: {
                        Capsule().fill(.primary.opacity(0.75))
                            .frame(width: 3, height: 8)
                    }
                    .frame(width: 24, height: 12)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
                    .position(x: x(marker.time, width), y: y)
                    .accessibilityLabel(markerAccessibilityLabel(marker))
                }
            }
        }
        .frame(height: 12)
    }

    private func x(_ time: Double, _ width: CGFloat) -> CGFloat {
        inset + width * CGFloat(min(1, max(0, time / max(1, duration))))
    }
}
