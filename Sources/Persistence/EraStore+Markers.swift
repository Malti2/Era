import Foundation
import SwiftData

// Notizen am Song und Marker an Versionen.
extension EraStore {
    static let maxNotesLength = 5000

    /// Speichert die Notiz (getrimmt, begrenzt). Gibt zurueck, ob sich etwas geaendert hat.
    @discardableResult
    func setNotes(_ notes: String, for song: Song) -> Bool {
        let song = resolve(song)
        let cleaned = String(notes.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxNotesLength))
        guard cleaned != song.notes else { return false }
        song.notes = cleaned
        save()
        return true
    }

    /// Setzt einen Marker; liegt dort schon einer, kommt dieser zurueck (und ein Label wird nachgetragen).
    @discardableResult
    func addMarker(at time: Double, label: String = "", to version: SongVersion) -> VersionMarker? {
        let version = resolve(version)
        guard let result = VersionMarkers.adding(at: time, label: label, duration: version.duration > 0 ? version.duration : nil,
                                                 to: version.markers) else { return nil }
        guard result.isNew else {
            if !VersionMarkers.cleaned(label: label).isEmpty, result.marker.label.isEmpty {
                renameMarker(result.marker.id, to: label, in: version)
            }
            return result.marker
        }
        version.markers = result.markers
        save()
        return result.marker
    }

    func removeMarker(_ id: UUID, from version: SongVersion) {
        let version = resolve(version)
        version.markers = VersionMarkers.removing(id, from: version.markers)
        save()
    }

    func renameMarker(_ id: UUID, to label: String, in version: SongVersion) {
        let version = resolve(version)
        version.markers = VersionMarkers.renaming(id, to: label, in: version.markers)
        save()
    }

    func clearMarkers(of version: SongVersion) {
        let version = resolve(version)
        version.markersJSON = ""
        save()
    }
}
