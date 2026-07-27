import SwiftUI

struct TagBarView: View {
    @Binding var selectedTags: Set<String>
    let allTags: [String]
    let onPresetTap: () -> Void
    let onPresetLongPress: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            // Preset icon button - minimal icon without background
            Button(action: onPresetTap) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(.white)
            }
            .simultaneousGesture(LongPressGesture().onEnded { _ in
                onPresetLongPress()
            })
            // Tag chips scroll view
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(allTags, id: \ .self) { tag in
                        let isSelected = selectedTags.contains(tag)
                        Text(tag)
                            .font(.caption)
                            .foregroundColor(isSelected ? .black : .white.opacity(0.7))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(isSelected ? Color.white : Color.black.opacity(0.6))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isSelected ? Color.clear : Color.gray.opacity(0.5), lineWidth: 1)
                            )
                            .onTapGesture {
                                if isSelected {
                                    selectedTags.remove(tag)
                                } else {
                                    selectedTags.insert(tag)
                                }
                            }
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

struct TagBarView_Previews: PreviewProvider {
    static var previews: some View {
        TagBarView(selectedTags: .constant(["#chill"]), allTags: ["#chill", "#late", "#unreleased"], onPresetTap: {}, onPresetLongPress: {})
            .background(Color.black)
    }
}
