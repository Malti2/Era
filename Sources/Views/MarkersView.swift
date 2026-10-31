import SwiftUI

// Marker einer Version als Liste: antippen springt hin, Wischen loescht, Halten benennt um.
struct MarkersSheet: View {
    let version: SongVersion
    let onSelect: (VersionMarker) -> Void
    @EnvironmentObject private var store: EraStore
    @Environment(\.dismiss) private var dismiss
    @State private var markerToRename: VersionMarker?
    @State private var renameText = ""

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
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.fontWeight(.semibold) }
            }
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

    private func beginRename(_ marker: VersionMarker) {
        renameText = marker.label
        markerToRename = marker
    }
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
    }
}

/// Dezente Skala unter dem Scrubber: Marker als kleine Striche, aktive A-B-Schleife als Band.
struct ScrubberOverlay: View {
    let markers: [VersionMarker]
    let loopStart: Double?
    let loopEnd: Double?
    let duration: Double

    // Slider-Daumen sitzt innen: Skala entsprechend einruecken.
    private let inset: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width - inset * 2)
            let y = geo.size.height - 3
            func x(_ time: Double) -> CGFloat { inset + width * CGFloat(min(1, max(0, time / max(1, duration)))) }
            ZStack(alignment: .topLeading) {
                if let start = loopStart {
                    let endX = loopEnd.map(x) ?? x(start)
                    Capsule().fill(Color.accentColor.opacity(0.9))
                        .frame(width: max(3, endX - x(start)), height: 3)
                        .position(x: x(start) + max(3, endX - x(start)) / 2, y: y)
                }
                ForEach(markers) { marker in
                    Capsule().fill(.white.opacity(0.75))
                        .frame(width: 3, height: 8)
                        .position(x: x(marker.time), y: y)
                }
            }
        }
        .frame(height: 12)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
