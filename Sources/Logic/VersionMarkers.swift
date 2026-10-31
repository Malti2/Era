import Foundation

// Marker an einer Version: benannte Zeitpunkte ("Hook", "Beat-Drop", "Vocal-Take"),
// die man beim Hoeren setzt und spaeter wieder anspringt. Gespeichert als JSON-String
// an der Version (kein eigenes Schema), hier nur reine Foundation-Logik.

struct VersionMarker: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var time: Double
    var label: String
}

enum VersionMarkers {
    /// Marker naeher als das beieinander gelten als derselbe Punkt.
    static let mergeWindow = 1.0
    /// Nach "zurueck" muss der Marker mindestens so weit hinter uns liegen, sonst springt man auf der Stelle.
    static let previousGuard = 1.5
    static let maxCount = 200
    static let maxLabelLength = 60

    static func decode(_ json: String?) -> [VersionMarker] {
        guard let json, !json.isEmpty, let data = json.data(using: .utf8),
              let list = try? JSONDecoder().decode([VersionMarker].self, from: data) else { return [] }
        return sorted(list.filter { $0.time.isFinite && $0.time >= 0 })
    }

    static func encode(_ markers: [VersionMarker]) -> String {
        guard !markers.isEmpty, let data = try? JSONEncoder().encode(sorted(markers)) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func sorted(_ markers: [VersionMarker]) -> [VersionMarker] {
        markers.sorted { $0.time != $1.time ? $0.time < $1.time : $0.label < $1.label }
    }

    static func cleaned(label: String) -> String {
        String(label.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLabelLength))
    }

    /// Setzt einen Marker bei `time`. Liegt dort schon einer, wird er zurueckgegeben statt dupliziert
    /// (`isNew == false`). Ohne Label bleibt es leer - die Oberflaeche zeigt dann die Zeit.
    static func adding(at time: Double, label: String = "", duration: Double? = nil,
                       to markers: [VersionMarker]) -> (markers: [VersionMarker], marker: VersionMarker, isNew: Bool)? {
        guard time.isFinite, time >= 0 else { return nil }
        let clamped = duration.map { min(time, max(0, $0)) } ?? time
        let rounded = (clamped * 10).rounded() / 10
        if let existing = markers.first(where: { abs($0.time - rounded) < mergeWindow }) {
            return (markers, existing, false)
        }
        guard markers.count < maxCount else { return nil }
        let marker = VersionMarker(time: rounded, label: cleaned(label: label))
        return (sorted(markers + [marker]), marker, true)
    }

    static func removing(_ id: UUID, from markers: [VersionMarker]) -> [VersionMarker] {
        markers.filter { $0.id != id }
    }

    static func renaming(_ id: UUID, to label: String, in markers: [VersionMarker]) -> [VersionMarker] {
        markers.map { marker in
            guard marker.id == id else { return marker }
            var copy = marker
            copy.label = cleaned(label: label)
            return copy
        }
    }

    static func next(after time: Double, in markers: [VersionMarker]) -> VersionMarker? {
        sorted(markers).first { $0.time > time + 0.25 }
    }

    static func previous(before time: Double, in markers: [VersionMarker]) -> VersionMarker? {
        sorted(markers).last { $0.time < time - previousGuard }
    }

    /// Marker, bei dem die Wiedergabe gerade steht (oder der zuletzt passiert wurde, wenn er nicht weiter als `within` zurueckliegt).
    static func current(at time: Double, in markers: [VersionMarker], within: Double = 0.75) -> VersionMarker? {
        sorted(markers).last { $0.time <= time + 0.1 && time - $0.time <= within }
    }

    /// Relative Positionen (0...1) fuer die Skala unter dem Scrubber.
    static func fractions(of markers: [VersionMarker], duration: Double) -> [Double] {
        guard duration > 0 else { return [] }
        return markers.map { min(1, max(0, $0.time / duration)) }
    }

    /// Beim Zusammenfuehren von Songs bleiben beide Notizen erhalten.
    static func mergedNotes(_ target: String, _ source: String) -> String {
        let a = target.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty { return b }
        if b.isEmpty || a == b || a.contains(b) { return a }
        return a + "\n\n" + b
    }
}
