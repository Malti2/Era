# Era – Projektgedächtnis (für autonome Sessions)

Hobbyprojekt von Malte: private-first Musikbibliothek für iPhone/iPad/Mac Catalyst (Swift, SwiftUI, SwiftData, iOS 18+, Liquid Glass ab iOS 26 hinter `#available`, siehe `App/Compat.swift`). Alles lokal, kein Server/Tracking.

## Struktur
- `project.yml` → xcodegen (`xcodegen generate` erzeugt Era.xcodeproj). `Sources/` ist komplett Target-Quelle (neue Dateien werden automatisch aufgenommen). Targets: Era, EraShareExtension, EraTests (`Tests/`).
- `Sources/Model/`: `Models.swift` (SwiftData: Song > SongVersion, Tag, Pack, Playlist/PlaylistEntry, PlayEvent), reine Logik ohne SwiftData: `StatsCalculator`, `DuplicateFinder`, `LibrarySearch`, `HomeShelves`; `DemoSeed` (Screenshots, `--era-demo`).
- `Sources/Persistence/Persistence.swift`: `EraStore` (MainActor, eigener ModelContext, Repository-Protokolle, `resolve()` vor jedem Schreiben!), `LibraryFiles`, Container-Recovery.
- `Sources/Services/`: PlayerEngine (Wiedergabe, Queue, Sleep-Timer, PlayEvents), ImportManager, BackupService (JSON-Export v2 inkl. Hörverlauf, `restore` = Merge per ID, nur wenn Audiodatei noch da), MetadataService, UpdateService (GitHub-Releases), SpotlightIndexer, EraShortcuts, IntelligenceService.
- `Sources/Views/`: Home, Library (Songs/Alben/Künstler/Playlists, Sort persistiert), Search, Packs ("Collections"), NowPlaying, SongDetail, Stats (Swift Charts), Duplicates, Settings, Components (Artwork, SongRow, MiniPlayer).
- Launch-Argumente für Screenshots: `--era-demo`, `--era-library`, `--era-stats` usw. (siehe ContentView/LibraryView init).

## Befehle
- Lokalisierung: `python3 Scripts/check-localizations.py` (Keys = englischer Text; Sprachen de/en/es/fr in `Sources/Resources/<l>.lproj/Localizable.strings`; de ist Referenz-Keyset). Neue UI-Texte in allen 4 Dateien ergänzen.
- Build/Tests nur auf macOS/CI: `xcodebuild … test` (siehe `.github/workflows`). Im Linux-Container gibt es KEINEN Swift-Compiler (swift.org per Proxy gesperrt, 403) → nicht erneut versuchen; Signaturen per Grep prüfen, Diff kritisch lesen.

## Konventionen
- Neue Logik als reine Structs/Enums in `Model/` + Unit-Tests in `Tests/`; Views dünn halten.
- Kommentare knapp (de/en gemischt ok), UI ruhig: System-Listen/-Farben, Accent-Tint, keine Wildwuchs-Einstellungen/Tabs.
- Nur ein Eintrag pro Song in Playlists. Deutsche Umlaute in Strings ok.
- Branch-Arbeit: Nightly-Sessions auf `claude/nightly`, kein PR/Force-Push, einmal pushen.

## Stolperfallen
- `DocumentPicker` (UIKit) statt `.fileImporter` (iOS-Bug).
- Schema-Änderungen an @Model brauchen Migration/Defaults; Backup-Format abwärtskompatibel halten (optionale Felder).
- `PlayerEngine.play(_:from:)` setzt die Queue; Regale/Listen sollten die ganze Liste übergeben.

## Ideen-Backlog
- Backup/Restore auch Artwork-Dateien und optional Audio (ZIP) einschließen.
- Auto-Backup in iCloud Drive / Erinnerung nach X Tagen.
- iPad: Sidebar-Layout statt Tab-Bar, Mehrspalten-Library.
- Album-/Künstler-Detailseiten mit Stats pro Künstler; Jahresrückblick ("Era Wrapped") aus PlayEvents.
- Mehrfachauswahl in der Library (Tags/Playlist/Löschen in einem Rutsch).
- Performance: Library-Listen bei >5k Songs (Query-Filter statt In-Memory-Sort).
- Lyrics/Notizen pro Version.
