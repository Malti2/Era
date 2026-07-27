import SwiftUI
import SwiftData

/// A horizontal tag selector with a high‑end Liquid Glass aesthetic.
/// It uses a layered frosted‑glass background, a subtle white inner border,
/// continuous rounded corners and a faint elevation shadow to match Apple’s
/// Human Interface Guidelines for Materials and Liquid Glass.
struct TagBarView: View {
    @Binding var selectedTags: Set<Tag>
    var allTags: [Tag]
    var presetAction: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Preset picker icon – tap opens picker, long‑press saves preset.
                Button(action: presetAction) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(.white)
                        .padding(8)
                }
                .contextMenu {
                    Button("Save Current Tags as Preset") {
                        // Context‑menu placeholder – actual save logic lives in the view model.
                    }
                }

                ForEach(allTags) { tag in
                    let isSelected = selectedTags.contains(tag)
                    Button(action: {
                        if isSelected {
                            selectedTags.remove(tag)
                        } else {
                            selectedTags.insert(tag)
                        }
                    }) {
                        Text(tag.name)
                            .font(.subheadline)
                            .foregroundColor(isSelected ? .black : .white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                // Multi‑layered glass effect.
                                ZStack {
                                    // Base material – ultra thin frosted glass.
                                    .ultraThinMaterial
                                    // Subtle specular highlight.
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.white.opacity(0.2), Color.clear]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing)
                                }
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
                    }
                }
            }
            .padding(.vertical, 6)
        }
        // Overall container styling – same layered glass with inner stroke.
        .background(
            ZStack {
                .ultraThinMaterial
                LinearGradient(
                    gradient: Gradient(colors: [Color.white.opacity(0.15), Color.clear]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.5), radius: 10, x: 0, y: 5)
    }
}
