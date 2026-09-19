# Era

Era is a private-first music library for iPhone, iPad, and Mac. It keeps released tracks, unreleased songs, demos, alternate versions, and personal audio files together in one local library.

<p align="center">
  <img src="Sources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" alt="Era app icon" width="160">
</p>

## Highlights

- Import MP3, M4A, WAV, FLAC, and other audio files from the Files app
- Organize music with tags, packs, playlists, song status, and alternate versions
- Create smart playlists from a natural-language description with Apple Intelligence (on supported devices)
- Edit metadata without changing the original audio files
- Play entirely offline with queue editing, playback speed, seek controls, and resume position
- Keep music playing in the background with lock screen and Control Center controls
- Switch on optional vinyl crackle, gapless playback, or crossfade transitions
- Review local listening stats: monthly plays, time listened, top tracks, and top artists
- Find songs through Core Spotlight and control playback with App Shortcuts and Siri
- Keep the library and audio files on the device, with no server, account, tracking, or analytics
- Use native Apple frameworks and system components throughout the app

## Platforms

| Platform | Status | Distribution |
| --- | --- | --- |
| iPhone and iPad | iOS 18 or later | Unsigned IPA for sideloading |
| Mac | Mac Catalyst | Unsigned DMG and ZIP |

The distributed builds are unsigned and are intended for personal testing. Installing them requires a compatible sideloading or local-signing setup. macOS may require a manual security approval because the Mac build is not signed or notarized.

## Download

The latest builds are available on the [Releases page](https://github.com/Malti2/Era/releases/latest):

- `Era-unsigned.ipa` for iPhone and iPad
- `Era-macOS-Catalyst-unsigned.dmg` for Mac
- `Era-macOS-Catalyst-unsigned.zip` as an alternative Mac package when included in the release

## Build from source

### Requirements

- macOS
- Xcode 26 or newer
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

### Generate the Xcode project

```bash
brew install xcodegen
xcodegen generate --spec project.yml
open Era.xcodeproj
```

The repository intentionally stores `project.yml` instead of a generated Xcode project.

### Install a ready-made build

Most users should download the latest IPA or DMG from the [Releases page](https://github.com/Malti2/Era/releases/latest). You do not need access to this repository's GitHub Actions.

### Build an unsigned IPA yourself

GitHub only lets repository collaborators run this repository's workflow manually. To build with your own GitHub account:

1. Fork this repository.
2. Open the **Actions** tab in your fork and enable workflows if GitHub asks.
3. Select the **Era** workflow and choose **Run workflow**.
4. Download the generated IPA, DMG, ZIP, and screenshots from the completed run's artifacts.

The workflow also runs automatically when you push to `main` in your fork. You can also generate `Era.xcodeproj` with XcodeGen and build locally on a Mac.

## Project structure

```text
.github/workflows/   Continuous integration and release artifacts
ShareExtension/      Share extension for importing files
Sources/App/          App entry point, navigation, and settings model
Sources/Model/        SwiftData models and demo content
Sources/Persistence/  Repositories and local file storage
Sources/Services/     Import, playback, metadata, backup, Spotlight, and shortcuts
Sources/Views/        SwiftUI screens and reusable components
project.yml           XcodeGen project definition
DECISIONS.md          Architecture and product decisions
```

## Privacy

Era does not use an application server. The music library, metadata, and imported audio remain in the app's local container. Spotlight indexing is on-device and can be disabled in Settings.

## Technical notes

- Swift and SwiftUI
- SwiftData for local persistence
- AVFoundation and MediaPlayer for playback
- Core Spotlight for system search
- App Intents for Shortcuts and Siri
- UIKit document picker for reliable imports on physical devices
- Mac Catalyst for the Mac build
- Bundle identifier: `de.malte.era`

## License

No open-source license is currently granted. The source is publicly visible for testing and review, but all rights are reserved unless a license is added later.
