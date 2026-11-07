import Foundation

// Operator-Hilfe fuer die Suche: Beispiele, die per Tipp in die Suche uebernommen werden.
// `title` ist der englische Lokalisierungsschluessel; `example` ist, was in das Suchfeld wandert.

struct SearchHelpEntry: Equatable, Identifiable {
    var example: String
    var title: String
    /// Muss die Eingabe mindestens einen Filter ergeben (false fuer Phrasen und Ausschluesse von Woertern).
    var isFilter = true
    var id: String { example }
}

struct SearchHelpGroup: Equatable, Identifiable {
    var title: String
    var entries: [SearchHelpEntry]
    var id: String { title }
}

enum SearchHelp {
    static let groups: [SearchHelpGroup] = [
        SearchHelpGroup(title: "Where to Look", entries: [
            SearchHelpEntry(example: "tag:demo", title: "Songs with a tag"),
            SearchHelpEntry(example: "status:leak", title: "Songs with a status"),
            SearchHelpEntry(example: "artist:\"Night Drive\"", title: "Songs by an artist"),
            SearchHelpEntry(example: "album:sketches", title: "Songs on an album"),
            SearchHelpEntry(example: "era:\"Synth Era\"", title: "Songs from an era or project"),
            SearchHelpEntry(example: "version:v2", title: "Songs that have a version with this name"),
            SearchHelpEntry(example: "year:2018-2020", title: "Songs from a range of years"),
        ]),
        SearchHelpGroup(title: "Listening", entries: [
            SearchHelpEntry(example: "fav", title: "Favorites"),
            SearchHelpEntry(example: "unplayed", title: "Songs you have never played"),
            SearchHelpEntry(example: "plays:>5", title: "Played more than five times"),
            SearchHelpEntry(example: "played:30d", title: "Played in the last 30 days"),
            SearchHelpEntry(example: "played:>90d", title: "Not played for over 90 days"),
        ]),
        SearchHelpGroup(title: "Library", entries: [
            SearchHelpEntry(example: "added:7d", title: "Added in the last 7 days"),
            SearchHelpEntry(example: "added:2024", title: "Added in a calendar year"),
            SearchHelpEntry(example: "length:>5m", title: "Longer than five minutes"),
            SearchHelpEntry(example: "length:<1m", title: "Shorter than one minute"),
            SearchHelpEntry(example: "versions:>1", title: "Songs with several versions"),
            SearchHelpEntry(example: "has:notes", title: "Songs with notes"),
            SearchHelpEntry(example: "has:markers", title: "Songs with markers"),
        ]),
        SearchHelpGroup(title: "Combine", entries: [
            SearchHelpEntry(example: "\"blue hour\"", title: "Exact phrase", isFilter: false),
            SearchHelpEntry(example: "-tag:demo", title: "Leave out songs with this tag"),
            SearchHelpEntry(example: "-live", title: "Leave out songs containing a word", isFilter: false),
            SearchHelpEntry(example: "tag:demo added:30d -has:notes", title: "Everything combined: all conditions must match"),
        ]),
    ]

    static var allEntries: [SearchHelpEntry] { groups.flatMap(\.entries) }
}
