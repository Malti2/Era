# Era – Projektgedächtnis für Claude-Sessions

## Zweck
Era ist eine private, offline-first Musikbibliothek (iPhone/iPad, Mac Catalyst) für Releases, Unreleased, Demos und alternative
Versionen. Alles bleibt lokal: kein Server, kein Account, kein Tracking. Distribution: unsigned IPA/DMG per GitHub Releases + AltStore-Source.

## Architektur (Swift 5-Modus, SwiftUI + SwiftData, iOS 18+, Xcode 26, Projekt via XcodeGen)
- `Sources/App` – `EraApp` (Container, Store, Environment-Objekte), `ContentView` (TabView Home/Collections/Library/Search,
  Sheets, Deep Links, Fehler-Toast), `AppSettings` (UserDefaults-Keys), `Compat` (Liquid-Glass-Helfer hinter `#available`).
- `Sources/Model` – SwiftData-Modelle in `Models.swift`: `Song` (Identität) → `SongVersion` (Datei/Hash/Dauer), `Tag` (Status = reservierte Tags),
  `Pack`, `Playlist`/`PlaylistEntry`, `PlayEvent`. `Song+Search.swift` = Adapter zur reinen Logik. `DemoSeed` für Screenshots.
- `Sources/Persistence/Persistence.swift` – `Persistence.makeContainer`, `EraStore` (alle Schreibzugriffe; Repository-Protokolle,
  `resolve()` vor jedem Write!), `LibraryFiles`/`VersionFiles` (Dateien im App-Container).
- `Sources/Logic` – **reine Foundation-Logik ohne SwiftData/UIKit** (auf Linux testbar): `SongSearch`, `LibraryOrdering` (Sortierung/Gruppierung),
  `LibraryBackup` (Format, Restore-Planung), `LibraryHealth` (Check), `PlaybackSession` (Snapshot + `ShuffleBag`), `SleepTimerState`, `Reordering`,
  `StatsCalculator` (Hörstatistik, Streak, Zeiträume, Tageszeit/Wochentag), `LibraryFilter` (Favoriten/Status/Tags), `PlaylistTools` (Sortierung, Text-Export), `HomeShelves` (Wiederentdecken/Nicht gespielt), `BulkSelection` (+ `BulkTagging`, `TagRename`), `ABLoop`, `VersionDetails`.
- `Sources/Services` – `PlayerEngine` (AVAudioPlayer, Queue, Gapless/Crossfade, Sleep, Session-Restore), `ImportManager`, `BackupService`
  (+ `LibraryMaintenance`: Restore & Reparaturen), `MetadataService`, `ArtworkCache`, Spotlight/Shortcuts/Intelligence/Update.
- `Sources/Views` – `LibraryView` (Songs/Albums/Artists/Playlists), `SearchView`, `HomeView`, `PacksView` ("Collections"), `SongDetailView`
  (+ `SongContextMenu`), `PlaylistDetailView`, `PlaylistPickerSheet` (zentral über `PlaylistPickerCoordinator`), `NowPlayingView`,
  `SettingsView` → `LibraryToolsView` (Backup/Restore/Check), `TagsView` (Tag-Verwaltung), `StatsView` (Swift Charts), `MetadataEditView`, `VersionEditView`,
  `BulkTagSheet`; Mehrfachauswahl steckt in `LibraryView` (Sort-Menü → "Select Songs"). Bulk-/Tag-Schreibzugriffe: `Persistence/EraStore+Bulk.swift`; Playlist-Sortierung/Duplizieren: `EraStore+Playlists.swift`; Version-Cover: `EraStore+Artwork.swift` (+ `ArtworkImporter`). `App/PlaybackCommands.swift` = Mac/iPad-Tastaturbefehle (⌘P, ⌘←/→); TabView ist `.sidebarAdaptable`.
- `Tests` – XCTest: `StoreTests`, `PlaylistStoreTests`, `LibraryMaintenanceTests` (in-memory SwiftData); `Tests/Logic/*` = Tests der reinen Logik.
- `ShareExtension`, `Scripts` (Release/AltStore/Lokalisierung), `docs/source.json` (AltStore), `.github/workflows` (PR-Check, Release).

## Befehle
- Projekt: `xcodegen generate` → `xcodebuild -project Era.xcodeproj -scheme Era -destination 'id=<sim>' CODE_SIGNING_ALLOWED=NO test` (nur macOS/CI).
- Lokalisierung: `python3 Scripts/check-localizations.py` (de ist Referenz; en/es/fr müssen alle Keys haben). CI lintet mit `swiftlint --lenient`.

## Konventionen & Design
- Ruhige, native Optik: Systemfarben/-materialien, `eraGlass*`/`eraProminentButton` aus `Compat.swift`, SF Symbols, wenige Tabs (4),
  keine Wildwuchs-Einstellungen – Unterfunktionen wandern in Unterseiten (z. B. Backup & Wartung statt eigener Settings-Sektionen).
- Schreibzugriffe immer über `EraStore` (testbar, ruft `save()`); Logik zuerst in `Sources/Logic` bzw. Store, Views bleiben dünn.
- Kommentare knapp, gemischt Deutsch/Englisch (Bestand); Typen/Funktionen englisch. Neue Texte: `Text("English key")` bzw. `String(localized:)`
  und in **allen vier** `Sources/Resources/*.lproj/Localizable.strings` ergänzen; Plurale (`%lld tracks`) in `Localizable.stringsdict`.
- Alte Keys wie "Erstellen"/"Wiedergeben"/"Verwerfen" sind deutsch im Code (Altlast, nicht kopieren).
- Launch-Argumente `--era-demo`, `--era-player`, … steuern Screenshot-Modi (siehe `ContentView`/`LibraryView` init).
- Keine neuen Abhängigkeiten ohne guten Grund; keine Secrets.

## Stolperfallen
- Linux-Tests laufen mit: Chroot-Paket (siehe unten) + `swift test`; `localizedStandardCompare` verhält sich auf Linux bei Groß/Klein-Gleichstand anders → in Tests nur eindeutige Fälle prüfen.
- Toolchain-Setup klappt (getestet): Layer von `library/swift:6.2-jammy` nach `/opt/swiftroot` entpacken (Token-Request kann beim ersten Versuch am Rate-Limit scheitern → wiederholen), `mount --bind /dev`, `mount -t proc`, Paket unter `/opt/swiftroot/work/Era` mit Symlinks. Zusätzlich: `swiftc -parse <datei>` im chroot prüft die Syntax beliebiger App-Dateien (Typen werden nicht geprüft).
- Im Cloud-Container ist **kein Swift vorinstalliert**, swift.org/Docker-Daemon sind gesperrt, aber `registry-1.docker.io` ist erreichbar:
  Image `swift:6.2-jammy` per Registry-API (Token via auth.docker.io, Layer-Blobs mit curl|tar) in ein rootfs entpacken, dann
  `mount --bind /dev`, `mount -t proc`, `chroot rootfs env LD_LIBRARY_PATH=/usr/lib/swift/linux PATH=/usr/bin:/bin swift test`.
  (Ohne `/dev` liefert `UUID()` konstante Werte!) SwiftPM-Paket "Era" mit Symlinks auf `Sources/Logic` + `Tests/Logic` baut und testet die
  reine Logik. **SwiftUI/SwiftData/AVFoundation lassen sich dort nicht kompilieren** → App-Code besonders sorgfältig gegen bestehende Signaturen prüfen.
- `Sources/Logic` darf nur Foundation importieren (sonst bricht der Linux-Check); Namen von Enum-Cases und Properties nicht doppeln (z. B. `title`).
- Sheets innerhalb von `.contextMenu`-Inhalten verschwinden mit dem Menü → zentrale Koordinatoren (siehe `PlaylistPickerCoordinator`).
- SwiftData-Schema nicht ohne Migrationsplan ändern (Fallback in `makeContainer` sichert nur die alte DB).
- Der Store besitzt einen eigenen `ModelContext`; Views liefern Modelle aus dem Environment-Context → vor Writes `resolve()`.

## Ideen-Backlog (noch nicht umgesetzt)
- Mehrfachauswahl auch für Alben/Künstler-Detail und Playlists (Logik `BulkSelection` ist generisch).
- iPad/Mac: Tastaturkürzel in der Bibliothek (⌘F → Suche), eigenes Split-View-Layout für Library/Detail.
- Stats: Jahresrückblick, Top-Alben (PlayEvent hat kein Album-Feld → Schema); Spotlight pro Song aktualisieren statt Komplett-Reindex.
- Dynamic-Type-Audit der festen Frames (50pt-Artwork, 44pt-Buttons, Selektionsleiste).
- Lyrics/Notizen pro Song (SwiftData-Schema → Migration beachten); A-B-Loop-Marker auf dem Scrubber zeichnen.
- Library-Filter auch für Alben/Künstler; Filter merken (AppStorage).
- `SongContextMenu`-Sheets (VersionDrawer, Share) auf Koordinator umstellen und auf dem Gerät prüfen.
- UI-Screenshots/Launch-Argumente für Tags, Selektionsmodus, Version-Editor ergänzen.
