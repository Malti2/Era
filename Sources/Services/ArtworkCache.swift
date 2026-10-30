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

// Bereitet ein gewaehltes Foto als Cover auf: begrenzte Kantenlaenge, JPEG, korrekte Ausrichtung.
enum ArtworkImporter {
    static func prepare(_ data: Data, maxSide: CGFloat = 1200) -> Data? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, maxSide / longest)
        let target = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: 0.88)
    }
}
