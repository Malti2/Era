import SwiftUI
import UIKit

// Moderner Vinyl-Platzhalter: dunkles Vinyl, klare Rillen, dezentes Label.
// Deterministisch pro Song, aber bewusst nahezu monochrom statt Regenbogen-CD.
struct DiscArtwork: View {
    let songID: UUID
    var statusName: String?
    var radius: CGFloat = 10
    private var params: DiscParams { DiscParams(id: songID) }

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = side * 0.43
            let labelRadius = side * 0.105
            let hole = side * 0.018

            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(.systemGray6)))
            let discRect = CGRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2)
            let vinyl = Gradient(colors: [Color(white: 0.22), Color(white: 0.055), Color(white: 0.15), Color(white: 0.035)])
            context.fill(Circle().path(in: discRect), with: .radialGradient(vinyl, center: center, startRadius: 0, endRadius: outer))

            var grooves = Path()
            var r = labelRadius * 1.25
            while r < outer * 0.97 {
                grooves.addEllipse(in: CGRect(x: center.x-r, y: center.y-r, width: r*2, height: r*2))
                r += max(2.1, side * 0.014)
            }
            context.stroke(grooves, with: .color(.white.opacity(0.12)), lineWidth: 0.55)

            var shine = Path()
            shine.addArc(center: center, radius: outer * 0.78, startAngle: .degrees(params.angle), endAngle: .degrees(params.angle + 48), clockwise: false)
            context.stroke(shine, with: .color(.white.opacity(0.2)), lineWidth: side * 0.035)

            let labelRect = CGRect(x: center.x-labelRadius, y: center.y-labelRadius, width: labelRadius*2, height: labelRadius*2)
            context.fill(Circle().path(in: labelRect), with: .color(Color(white: 0.74)))
            context.stroke(Circle().path(in: labelRect), with: .color(.black.opacity(0.22)), lineWidth: 1)
            let holeRect = CGRect(x: center.x-hole, y: center.y-hole, width: hole*2, height: hole*2)
            context.fill(Circle().path(in: holeRect), with: .color(Color(.systemGray6)))
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(.black.opacity(0.08), lineWidth: 0.5))
    }
}

struct DiscParams {
    let angle: Double
    init(id: UUID) {
        var bytes: [UInt8] = []
        withUnsafeBytes(of: id.uuid) { bytes.append(contentsOf: $0) }
        angle = Double(bytes.first ?? 0) / 255 * 360
    }
}

enum DiscArtworkCache {
    static var cacheDir: URL {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("DiscArtwork-v2", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    @MainActor static func png(for songID: UUID, status: String?, size: CGFloat = 1024) -> UIImage {
        let file = cacheDir.appendingPathComponent("\\(songID.uuidString)-\\(Int(size)).png")
        if let data = try? Data(contentsOf: file), let image = UIImage(data: data) { return image }
        let renderer = ImageRenderer(content: DiscArtwork(songID: songID, statusName: status, radius: 0).frame(width: size, height: size))
        renderer.scale = 1
        let image = renderer.uiImage ?? UIImage()
        if let data = image.pngData() { try? data.write(to: file, options: .atomic) }
        return image
    }
}
