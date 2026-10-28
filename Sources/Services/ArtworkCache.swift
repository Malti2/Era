import UIKit

// Cover werden in Listen bei jedem Neuzeichnen gebraucht - ohne Cache las jede Zeile
// ihre Datei bei jedem Scroll-Schritt von der Platte und dekodierte sie neu.
enum ArtworkCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    static func image(for file: String) -> UIImage? {
        let key = file as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let data = try? Data(contentsOf: LibraryFiles.artworkURL(file)), let image = UIImage(data: data) else { return nil }
        // Vor-dekodiert, damit das erste Zeichnen nicht auf dem Main-Thread dekodiert.
        let ready = image.preparingForDisplay() ?? image
        let cost = Int(ready.size.width * ready.size.height * ready.scale * ready.scale * 4)
        cache.setObject(ready, forKey: key, cost: cost)
        return ready
    }

    static func evict(_ file: String) { cache.removeObject(forKey: file as NSString) }
}
