import SwiftUI
import UIKit

// Zentrale, echte Einstellungen (UserDefaults). Views binden per @AppStorage,
// der Player liest die Werte live ueber die statischen Helfer.
enum AppSettings {
    static let defaultRateKey = "settings.defaultRate"
    static let skipIntervalKey = "settings.skipInterval"
    static let pauseOnRouteChangeKey = "settings.pauseOnRouteChange"
    static let resumeAfterInterruptionKey = "settings.resumeAfterInterruption"
    static let hapticsEnabledKey = "settings.hapticsEnabled"
    static let spotlightEnabledKey = "settings.spotlightEnabled"
    static let hasOnboardedKey = "settings.hasCompletedOnboarding"
    static let crackleEnabledKey = "settings.crackleEnabled"
    static let crackleVolumeKey = "settings.crackleVolume"
    static let transitionStyleKey = "settings.transitionStyle"
    static let crossfadeSecondsKey = "settings.crossfadeSeconds"
    static let librarySectionKey = "settings.librarySection"
    static let hasSeenVersionsCoachKey = "settings.hasSeenVersionsCoach"

    static let skipIntervals = [5, 10, 15, 30]
    static let rates: [Double] = [0.75, 1.0, 1.25, 1.5, 2.0]
    static let crossfadeOptions = [2, 4, 6, 8, 12]

    enum TransitionStyle: String, CaseIterable, Identifiable {
        case off, gapless, crossfade
        var id: String { rawValue }
        var title: String {
            switch self {
            case .off: String(localized: "Off")
            case .gapless: String(localized: "Gapless")
            case .crossfade: String(localized: "Crossfade")
            }
        }
    }

    static func bool(_ key: String, default def: Bool = true) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil ? def : UserDefaults.standard.bool(forKey: key)
    }

    static var skipInterval: Double {
        let v = UserDefaults.standard.integer(forKey: skipIntervalKey)
        return Double(v > 0 ? v : 15)
    }

    static var defaultRate: Float {
        let v = UserDefaults.standard.double(forKey: defaultRateKey)
        return v > 0 ? Float(v) : 1.0
    }

    static var crackleVolume: Double {
        let v = UserDefaults.standard.double(forKey: crackleVolumeKey)
        return v > 0 ? v : 0.18
    }

    static var transitionStyle: TransitionStyle {
        TransitionStyle(rawValue: UserDefaults.standard.string(forKey: transitionStyleKey) ?? "off") ?? .off
    }

    static var crossfadeSeconds: Double {
        let v = UserDefaults.standard.integer(forKey: crossfadeSecondsKey)
        return Double(v > 0 ? v : 6)
    }
}

enum AppIconImage {
    static var uiImage: UIImage {
        if let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String],
           let name = files.last, let image = UIImage(named: name) {
            return image
        }
        return UIImage(named: "AppIcon") ?? UIImage()
    }
}
