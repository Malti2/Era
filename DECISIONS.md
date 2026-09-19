# Era - Entscheidungen (Spec 0: was nicht in der Spec steht, ist hier dokumentiert)

Build v27.0.0, Basis: v3.1 (commit e553ea4). Maltes Vorgaben: Apple Music komplett
weg, komplett offline/lokal (kein CloudKit, kein iCloud-Storage), alles andere aus
der Handoff-Spec rein. Versionsnummer Apple-orientiert: 27.0.0 (Major = kommendes Jahr).

## Vom Auftrag ueberschrieben
- **Kein MusicKit / Apple Music**: Spec-Schritt 8 entfaellt komplett. Kein Katalog,
  keine Katalog-Suche, kein Katalog-Artwork.
- **Kein CloudKit / Sync**: Spec-Schritt 9 entfaellt. Persistenz liegt trotzdem
  hinter Repository-Protokollen (`SongRepository`, `TagRepository`, `PackRepository`,
  `PlaylistRepository` in `Persistence.swift`) - ein Sync-Backend ist spaeter
  nachruestbar, ohne die App anzufassen.
- **Datei-Import per UIKit-`UIDocumentPickerViewController` (asCopy: true)** statt
  SwiftUI `.fileImporter`: `.fileImporter` schliesst auf echten iPhones den Picker
  nicht und feuert den Callback nie (bekannter iOS-Bug, in v3.1 live erlebt).
  `asCopy` braucht zusaetzlich keinen Security-Scoped-Zugriff.

## Selbst entschieden (Spec liess es offen)
- **Metadaten-Bearbeitung ist nicht-destruktiv**: Edits landen in der Era-Datenbank
  (Version-Overrides bzw. Song-Felder), die Audiodatei selbst wird nie veraendert.
  FLAC-Metadaten werden gelesen (eigener Vorbis-Comment-Parser, PICTURE-Block fuer
  Cover), aber nicht in die Datei zurueckgeschrieben.
- **Akzentfarbe**: System-Tint (kein eigener Farbverlauf wie in v3). Vorgabe war
  "keine eigene Design-Sprache".
- **Dark/Light Mode**: folgt dem System (v3 forcierte Dark Mode).
- **Deployment Target iOS 18.0**: alle iOS-26-APIs (Liquid Glass, Tab-Minimierung,
  Bottom-Accessory) hinter `#available`; iOS 18 bekommt klassische Materialien.
  Kompilierbarkeit fuer iOS 18 ist durch das Deployment Target abgesichert; ein
  iOS-18-Simulatorlauf entfaellt, weil der Runner nur die iOS-26-Runtime traegt
  (Download einer zweiten Runtime sprengt das CI-Zeitbudget).
- **String Catalog**: `Sources/Resources/Localizable.xcstrings`, Source-Language `de`.
  Deutsche Literale im Code sind die Source-Strings; der Catalog ist der
  Erweiterungspunkt fuer spaetere Sprachen.
- **Share Extension**: eigenes Target `EraShareExtension`. Unsigniert ohne
  App-Groups-Entitlement funktioniert der Datei-Handover nicht; die Extension faellt
  dann auf einen Hinweis-Dialog zurueck ("Era öffnen und dort importieren"). Mit
  signierter Installation + App Group `group.de.malte.era` landen Dateien in einer
  Inbox. (Spec 15.1: "Share Extension nur eingeschraenkt" unsigniert testbar.)
- **Dupe-Kriterium**: SHA-256 ueber dekodierte PCM-Frames plus Dauer (Toleranz 0,5 s).
  Exakter Hash-Match = "schon in der Bibliothek", keine zweite Version (Spec 4).
- **Automatische Verknuepfung**: nur Titel-Aehnlichkeit als Vorschlag im
  Massenimport ("Gehoert das zu X?"), nie automatisch (Spec 11.1).
- **Primäre Version**: erste importierte Version, manuell umstellbar im
  Song-Kontextmenue. Reihenfolge der Versionsliste: Jahr, dann Sort-Index.
- **Migration v3.1 -> v27**: die alte `library.json` wird beim ersten Start in das
  SwiftData-Modell uebernommen (Titel/Artist/Album/Favorit/PlayCount, Dateien
  bleiben liegen) und danach in `library-v3-migriert.json` umbenannt.
- **Monetarisierung**: alles frei, kein Feature-Flag noetig, solange es keine
  Bezahlfunktion gibt (Spec 16).

## Offen (bewusst nicht entschieden)
- iPad-/Mac-Optimierung (Spec: "spaeter"): Layout ist adaptiv (NavigationStack,
  Size Classes, keine fixen iPhone-Groessen), aber nicht iPad-verfeinert.

## Audio-Hash: AVAssetReader statt AVAudioFile
`AVAudioFile.read(into:)` wirft im Simulator (und potenziell auf manchen Geraeten) einen generischen Fehler beim PCM-Read. Der Dupe-Hash (SHA-256 ueber dekodierte PCM-Frames, Spec 13.3) dekodiert deshalb primaer ueber AVAssetReader (float32 PCM). AVAudioFile bleibt als Pfad fuer rohes FLAC, das AVAsset nicht oeffnet.

## 27.1.0 (2026-09-15): Native Tiefe statt Eigenbau

Maltes Vorgabe: ueberall native Apple-/SwiftUI-/UIKit-Komponenten und
Standardverhalten, begruendete Ausnahmen (z.B. UIDocumentPickerViewController)
bleiben. Apple Music weiterhin komplett draussen.

- **Queue bearbeiten**: "Als Naechstes" mit nativem EditButton, .onMove/.onDelete,
  "Queue leeren". Neu "Zum Schluss hinzufuegen" im Song-Kontextmenue.
- **Teilen**: Audiodateien ueber das native Share-Sheet (UIActivityViewController),
  im Song-Kontextmenue und pro Version im Detail. Nur wenn die Datei lokal existiert.
- **CoreSpotlight**: Songs werden in den privaten On-Device-Index geschrieben
  (Titel/Artist/Album/Tags/Versionen + Artwork-Thumbnail), Neuaufbau bei Start und
  nach jedem Import. Tap auf einen Spotlight-Treffer oeffnet Era und spielt den Song
  (CSSearchableItemActionType via onContinueUserActivity).
- **App Shortcuts / Siri**: AppShortcutsProvider mit drei Kurzbefehlen
  (Abspielen/Weiterhoeren, Pausieren, Naechster Titel). Steuern nur den lokalen
  Player, offline. PlayerEngine bekommt dafuer eine schwache Store-Referenz
  (resumeOrPlay: letzter Song oder einfach Play).
- **Now Playing**: nativer MPVolumeView-Lautstaerkeregler, Tempo-Auswahl
  (0.75-2x ueber AVAudioPlayer.enableRate), 15s-Sprungtasten
  (gobackward.15/goforward.15), haptisches Feedback via .sensoryFeedback
  (Favorit, Play/Pause).
- **AVAudioSession-Haerte**: Unterbrechung (Anruf/Siri) pausiert und nimmt bei
  .shouldResume wieder auf; Kopfhoerer/Bluetooth abgezogen pausiert
  (oldDeviceUnavailable). Beides Apple-Standardverhalten.
- **Fortsetzen-Position**: Song.resumePosition (SwiftData, additive Migration)
  wird bei Pause/Wechsel gesichert; Home-"Fortsetzen" springt an die Stelle.
- **Mediathek**: natives Sortier-Menue (Zuletzt/Titel/Kuenstler) in der Toolbar.
- **Home**: zusaetzliche Regale "Favoriten" und "Meist gespielt".
- **App-Icon**: iOS-18 Dark- und Tinted-Variante im Asset Catalog
  (luminosity-Appearances, Dark = invertiert, Tinted = Alpha-Maske).

### Simulator-Hinweis 27.1.0
- Der native MPVolumeView-Lautstaerkeregler rendert im iOS-Simulator leer
  (kein volumenfaehiger Ausgabe-Route) - auf dem Geraet ist er sichtbar.
  Bewusst trotzdem nativ, kein Ersatz-Slider.

## 27.1.0 - Einstellungen & Onboarding (Batch 5, 15.09.2026)
- Einstellungen: Info-Sektion "Wiedergabe" durch echte Einstellungen ersetzt:
  Standard-Tempo (0,75-2x), Sprungweite (5/10/15/30 s), Kopfhoererabzug-Pause,
  Fortsetzen nach Anruf, Haptik, Spotlight-Sichtbarkeit. Alle in UserDefaults
  (@AppStorage in den Views, PlayerEngine liest live ueber AppSettings).
- Datenschutz-Sektion aus den Einstellungen entfernt; Datenschutz gehoert in die
  Einfuehrung (Maltes Vorgabe). In den Einstellungen bleibt eine Kurzzeile.
- OnboardingView: natives 3-Seiten-Onboarding (Willkommen / Datenschutz /
  Grundeinstellungen) als Sheet beim ersten Start, Seiten via TabView(.page).
  Setzt hasCompletedOnboarding; im Screenshot-Modus (--era-demo) unterdrueckt,
  erzwingbar via --era-onboarding. "Einfuehrung erneut ansehen" in Einstellungen.
- SpotlightIndexer.clearAll() loescht den Index, wenn Spotlight deaktiviert wird.

## 2026-09-16: macOS ueber Mac Catalyst
- Era bleibt eine UIKit/SwiftUI-Codebasis. Mac Catalyst ist Apples direkter Weg, eine iPad-App mit gemeinsamem Projekt und Quellcode auf macOS zu bringen.
- Ein separates natives AppKit/macOS-Target waere wegen UIDocumentPicker, MediaPlayer, UIKit-Artwork und Share Extension eine zweite Plattformimplementierung ohne funktionalen Mehrwert fuer diese Runde.
- CI baut deshalb zusaetzlich ein unsigniertes Mac-Catalyst-Era.app und verpackt es als ZIP. Das ist fuer Intel und Apple Silicon vorgesehen; Installation ausserhalb des App Stores braucht spaeter Signierung/Notarisierung.
- Auslieferung zusaetzlich als DMG mit Era.app und Programme-Alias fuer klassische Drag-and-Drop-Installation. Ohne Developer-ID bleibt der Build unsigniert/unnotarisiert; macOS kann beim ersten Start eine Sicherheitsfreigabe verlangen.

## 27.7.0 (2026-09-19): Widget entfernt, Versions-Queue, Scrubbing

- **Home-Screen-Widget komplett entfernt** (Target `EraWidgetsExtension`, App Group
  `group.de.malte.era`, `EraShared`-Kanal): unsigniert sideloaded zeigte es ohnehin
  nur den Fallback, weil App Groups ohne Provisioning keinen geteilten Container
  bekommen. Die Share Extension behandelt das weiterhin selbst mit Hinweis-Dialog.
- **Ein Song = ein Queue-Slot**: Queues enthalten nur noch die eingestellte
  (primäre) Version pro Song. Beim Versionenwechsel im Player ersetzt
  `PlayerEngine.switchVersion` alle Versionen des Songs in der Queue durch die
  gewählte, statt sie anzuhäufen.
- **Scrubbing**: der Slider zieht auf lokalem State während des Drags; der echte
  Seek (inkl. Transition-Neuaufbau) feuert einmal beim Loslassen. Der 0,25s-Ticker
  aktualisiert die Lock-Screen-Anzeige nur noch als In-Place-Elapsed-Update statt
  pro Tick das Now-Playing-Info inkl. Artwork neu zu laden.

## 27.8.0 (2026-09-19): Playlist-Fixes, Ordner-Import, Update-Anzeige, Apple Intelligence

- **Playlists loeschen**: EraStore schreibt ueber seinen eigenen ModelContext,
  Views liefern Modelle aus dem SwiftUI-Environment-Context. `context.delete`
  auf ein fremd registriertes Modell war ein stiller No-Op - die Playlist blieb.
  Alle Schreibpfade (Song/Playlist/Pack/Tag loeschen, Playlist-Eintraege)
  loesen das Modell jetzt per `resolve(_:)` (persistentModelID) im Store-Context
  neu auf.
- **Keine Duplikate in Playlists**: `appendEntry` verweigert Songs, die schon in
  der Playlist sind; das Hinzufuegen-Sheet zeigt sie mit gruenem Haken und
  deaktiviert die Zeile.
- **Ordner-Import-Crash**: `UIDocumentPickerViewController(forOpeningContentTypes:
  [.folder], asCopy: true)` wirft beim Oeffnen - Ordner koennen nicht als Kopie
  geoeffnet werden. Der Ordner-Picker nutzt jetzt `asCopy: false`; ImportManager
  haelt die Security-Scoped-URL vom Staging bis zum Bestaetigen/Abbrechen offen
  (`holdScopes`/`releaseScopes`). Unterordner werden jetzt rekursiv eingelesen,
  versteckte Dateien (`.DS_Store`) uebersprungen.
- **Update-Drawer zeigte "99.0.0"**: das Launch-Sheet nutzte
  `availableRelease ?? demoRelease`; sobald der State auf downloading/downloaded
  wechselte, wurde `availableRelease` nil und die Demo-Version 99.0.0 erschien
  mitten im Flow. Neues `presentedRelease` bleibt ueber den ganzen Download
  stabil, die Demo-Version dient nur noch dem Screenshot-Flag.
- **Apple Intelligence (Foundation Models, iOS 26+)**: "Smart Playlist" in den
  Playlists - Playlist-Beschreibung in natuerlicher Sprache, das On-Device-Modell
  waehlt passende Songs aus der Mediathek (Titel/Artist/Album/Tags) und schlaegt
  einen Namen vor. Komplett hinter `SystemLanguageModel`-Verfuegbarkeit
  (`canImport` + `#available` + availability-Check); Geraete ohne Apple
  Intelligence sehen den Einstieg nicht, nichts crasht, nichts fehlt.


## 27.8.1 (2026-09-19): Smart-Playlist-Sprache

- Smart-Playlist-Namen folgen jetzt explizit der aktiven App-/Gerätesprache.
  Locale und Sprachname werden sowohl in den Session-Instruktionen als auch in
  der Anfrage mitgegeben; Song-Metadaten oder die Eingabesprache können die
  Ausgabesprache nicht mehr versehentlich bestimmen.
- Das strukturierte Namensfeld verlangt dieselbe aktive Sprache. Weitere vom
  Modell erzeugte sichtbare Texte gibt es in diesem Flow nicht; Fehler- und
  Statusmeldungen bleiben über die String Catalogs lokalisiert.
