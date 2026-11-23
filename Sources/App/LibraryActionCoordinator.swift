import SwiftUI

// Zentraler Schalter fuer Aktionen, die aus der Library heraus angestossen werden:
// Cmd+O (Import) und Cmd+N (neue Playlist) laufen ueber ContentView, damit sie auch
// greifen, wenn die Library in der Session noch nie offen war - die Observer lebten
// vorher in LibraryView und brauchten erst den Tab-Wechsel plus 0,35 s Wartezeit.
@MainActor
final class LibraryActionCoordinator: ObservableObject {
    @Published var showImporter = false
    @Published var showNewPlaylist = false

    func requestImport() { showImporter = true }
    func requestNewPlaylist() { showNewPlaylist = true }
}
