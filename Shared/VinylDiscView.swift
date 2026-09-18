import SwiftUI

// Small self-contained spinning vinyl for widgets and the Live Activity.
// Pure SwiftUI Canvas, no app dependencies.
struct VinylDiscView: View {
    let seed: UUID
    var isPlaying: Bool = true
    var spins: Bool = true

    private var shineAngle: Double {
        var bytes: [UInt8] = []
        withUnsafeBytes(of: seed.uuid) { bytes.append(contentsOf: $0) }
        return Double(bytes.first ?? 0) / 255 * 360
    }

    var body: some View {
        if spins {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { context in
                disc(angle: context.date.timeIntervalSinceReferenceDate * 100)
            }
        } else {
            disc(angle: 0)
        }
    }

    private func disc(angle: Double) -> some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = side * 0.48
            let labelRadius = side * 0.12
            let hole = side * 0.02

            let discRect = CGRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2)
            let vinyl = Gradient(colors: [Color(white: 0.24), Color(white: 0.06), Color(white: 0.16), Color(white: 0.04)])
            context.fill(Circle().path(in: discRect), with: .radialGradient(vinyl, center: center, startRadius: 0, endRadius: outer))

            var grooves = Path()
            var r = labelRadius * 1.3
            while r < outer * 0.97 {
                grooves.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
                r += max(1.6, side * 0.05)
            }
            context.stroke(grooves, with: .color(.white.opacity(0.14)), lineWidth: max(0.4, side * 0.006))

            var shine = Path()
            shine.addArc(center: center, radius: outer * 0.78,
                         startAngle: .degrees(shineAngle), endAngle: .degrees(shineAngle + 50), clockwise: false)
            context.stroke(shine, with: .color(.white.opacity(0.22)), lineWidth: side * 0.05)

            let labelRect = CGRect(x: center.x - labelRadius, y: center.y - labelRadius, width: labelRadius * 2, height: labelRadius * 2)
            context.fill(Circle().path(in: labelRect), with: .color(Color(white: 0.74)))
            let holeRect = CGRect(x: center.x - hole, y: center.y - hole, width: hole * 2, height: hole * 2)
            context.fill(Circle().path(in: holeRect), with: .color(.black.opacity(0.6)))
        }
        .rotationEffect(.degrees(angle.truncatingRemainder(dividingBy: 360)))
    }
}
