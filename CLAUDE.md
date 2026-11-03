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
  `StatsCalculator` (Hörstatistik, Streak, Zeiträume, Tageszeit/Wochentag), `LibraryFilter` (Favoriten/Status/Tags), `PlaylistTools` (Sortierung, Text-Export), `HomeShelves` (Wiederentdecken/Nicht gespielt), `BulkSelection` (+ `BulkTagging`, `TagRename`), `YearReview` (Jahresrückblick), `CollectionRule`/`CollectionName` (Sammlungs-Regel v2: dabei/ohne je Tag/Status, Alle/Eine-Modus, `labels` für Kurztext; Pack hat dafür `excludedTagIDs`/`excludedStatusNames`/`matchAny`, Backup-Felder optional), `AlphaSections` (A–Z-Abschnitte, in LibraryOrdering.swift), `ABLoop`, `VersionDetails`, `VersionMarkers` (Marker-JSON, Navigation, Notiz-Merge), `NoteSnippet` (Treffer-Ausschnitt), `BackupReminder`, `YearComparison` (Vorjahresvergleich), `SongListening` (Hörverlauf eines Songs, Monats-Buckets).
- `Sources/Services` – `PlayerEngine` (AVAudioPlayer, Queue, Gapless/Crossfade, Sleep, Session-Restore), `ImportManager`, `BackupService`
  (+ `LibraryMaintenance`: Restore & Reparaturen), `MetadataService`, `ArtworkCache`, Spotlight/Shortcuts/Intelligence/Update.
- `Sources/Views` – `LibraryView` (Songs/Albums/Artists/Playlists), `SearchView`, `HomeView`, `PacksView` ("Collections"), `SongDetailView`
  (+ `SongContextMenu`), `PlaylistDetailView`, `PlaylistPickerSheet` (zentral über `PlaylistPickerCoordinator`), `NowPlayingView`,
  `SettingsView` → `LibraryToolsView` (Backup/Restore/Check), `TagsView` (Tag-Verwaltung), `StatsView` (Swift Charts), `MetadataEditView`, `VersionEditView`,
  `BulkTagSheet`, `YearReviewView` (Stats → Year in Review, teilbare Karte per ImageRenderer), `CollectionEditorView` (Sammlungen anlegen/bearbeiten/löschen; Store-Seite: `EraStore+Collections.swift`); Mehrfachauswahl: `LibraryView`, `CollectionDetailView` (Album/Künstler) und `SongListView` (automatische Sammlungen) teilen sich `SongSelectionToolbar` + `SelectableSongRow` (`SongSelectionToolbar.swift`); Einstieg jeweils über das Menü → "Select Songs". Bulk-/Tag-Schreibzugriffe: `Persistence/EraStore+Bulk.swift`; Playlist-Sortierung/Duplizieren: `EraStore+Playlists.swift`; Version-Cover: `EraStore+Artwork.swift` (+ `ArtworkImporter`); Notizen/Marker: `EraStore+Markers.swift` (`Song.notes`, `SongVersion.markersJSON` – als String statt Schema-Typ; UI: `MarkersView.swift` = `MarkersSheet` + `ScrubberOverlay`, `SongNotesView`; Setzen in NowPlaying-Menü/⌘M). `App/PlaybackCommands.swift` = Mac/iPad-Tastaturbefehle (⌘P, ⌘←/→, ⌘O Import / ⌘N neue Playlist über `.eraImportMusic`/`.eraNewPlaylist`; `NavigationCommands`: ⌘1–4 Tabs, ⌘F Suche über `.eraSwitchScreen`-Notification); TabView ist `.sidebarAdaptable`.
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
- Toolchain-Setup 2026-11 (4. Lauf) wieder bestätigt: Pull-Skript lief trotz Rate-Limit nach ~4 Min durch; Package-Manifest für den Chroot: `Package.swift` mit Target `Era` (Sources/Era → Symlink auf Sources/Logic) + Test-Target `EraTests` (Tests/EraTests → Tests/Logic), swift-tools 5.9.
- Toolchain-Setup 2026-11 (2. Lauf) bestätigt: Pull-Skript mit Retry-Schleife im Hintergrund (`nohup`), nach ~8 Min fertig; danach `mount --bind /dev|/proc|/home/user/Era` und `swift test` im Chroot. Der App-Teil (SwiftUI/SwiftData) wird dort nur per `swiftc -parse` geprüft, nicht typgeprüft.
- WICHTIG: Vor Arbeitsbeginn `git fetch origin claude/nightly` – der Branch existiert und enthält den Stand aller früheren Läufe (nicht von main starten).
- Toolchain-Setup 2026-11 erneut bestätigt (Docker-Rate-Limit dauerte ~10 Min, Skript mit `sleep 60`-Retry in Hintergrund starten und währenddessen coden). `swiftc -parse` für App-Dateien; `swift test` im Chroot: 131 Logic-Tests.
- Linux-Tests laufen mit: Chroot-Paket (siehe unten) + `swift test`; `localizedStandardCompare` verhält sich auf Linux bei Groß/Klein-Gleichstand anders → in Tests nur eindeutige Fälle prüfen.
- Chroot-Kurzform: Package unter /opt/swiftroot/work/Era (Sources/Logic, Tests/Logic als Symlinks auf /home/user/Era, das per `mount --bind` nach /opt/swiftroot/home/user/Era gespiegelt wird), `chroot … swift test`; Syntax-Check: `swiftc -parse`. Docker-Hub-Rate-Limit: Manifest-Abruf in Schleife mit `sleep 60` wiederholen (kann mehrere Minuten dauern).
- Neue Sprachstrings: Schlüssel per kleinem Python-Skript an alle vier `.strings` anhängen; Plural-Keys mit Zahl brauchen Eintrag in jeder `.stringsdict`.
- Toolchain-Setup klappt (jede Session neu, ~3 Min; getestet 2026-10): Layer von `library/swift:6.2-jammy` nach `/opt/swiftroot` entpacken (Token-Request kann beim ersten Versuch am Rate-Limit scheitern → wiederholen), `mount --bind /dev`, `mount -t proc`, Paket unter `/opt/swiftroot/work/Era` mit Symlinks. Zusätzlich: `swiftc -parse <datei>` im chroot prüft die Syntax beliebiger App-Dateien (Typen werden nicht geprüft).
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
- Mehrfachauswahl noch für Playlist-Detail (Logik `BulkSelection` + `SongSelectionToolbar` sind generisch).
- Sammlungen: Play-on-Tap im PackDetailView, Regel-Gruppen (z. B. (A oder B) und nicht C).
- Year in Review: Top-Alben (PlayEvent hat kein Album-Feld), Vergleich zum Vorjahr, Auswahl beliebiger Zeiträume.
- iPad/Mac: eigenes Split-View-Layout für Library/Detail; ⌘N/⌘O funktionieren nur bei sichtbarer Playlist-Sektion/gefüllter Bibliothek.
- Song-Detail: Rang unter allen Songs, Hörverlauf-Detailliste; Queue-Playlist: Name-Vorschlag konfigurierbar.
- Relink beim Import (`StoreOutcome.relinked`) ist nur durch Gerätetest abgedeckt (braucht echte Audiodatei).
- Dynamic-Type-Audit: Listen-Cover nutzen `.scaledSquare()`; offen: feste 44pt-Buttons, Selektionsleiste, Now-Playing.
- Library-Filter-UI: A–Z-Sprungleiste (iOS 26 `sectionIndexLabel`) zusätzlich zu den Abschnitten.
- Marker: per Tipp auf Scrubber-Strich springen, Marker in Siri/Shortcuts, Marker-Export; Notizen im CSV-Export.
- Library-Filter auch für Alben/Künstler (Songs-Filter wird bereits gemerkt, `settings.libraryFilter`).
- DemoSeed um Notizen/Marker erweitern (Screenshots), Launch-Argument für Marker-Sheet.
- `SongContextMenu`-Sheets (VersionDrawer, Share) auf Koordinator umstellen und auf dem Gerät prüfen.
- UI-Screenshots/Launch-Argumente für Tags, Selektionsmodus, Version-Editor ergänzen.
