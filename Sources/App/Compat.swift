import SwiftUI

// iOS 18 Deployment Target: Liquid Glass laeuft nur auf iOS 26+, alles hinter
// #available. Darunter klassische Materialien - keine handgemalte Optik.
extension View {
    @ViewBuilder func eraTabMinimize() -> some View {
        if #available(iOS 26, *) { self.tabBarMinimizeBehavior(.onScrollDown) } else { self }
    }
    @ViewBuilder func eraGlassCircle() -> some View {
        if #available(iOS 26, *) { self.glassEffect(.regular.interactive(), in: .circle) }
        else { self.background(.ultraThinMaterial, in: Circle()) }
    }
    @ViewBuilder func eraGlassCapsule() -> some View {
        if #available(iOS 26, *) { self.glassEffect(.regular, in: .capsule) }
        else { self.background(.regularMaterial, in: Capsule()) }
    }
    @ViewBuilder func eraGlassRect(_ radius: CGFloat) -> some View {
        if #available(iOS 26, *) { self.glassEffect(.regular, in: .rect(cornerRadius: radius)) }
        else { self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous)) }
    }
    @ViewBuilder func eraProminentButton() -> some View {
        if #available(iOS 26, *) { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.borderedProminent) }
    }
}
