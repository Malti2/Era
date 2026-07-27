import SwiftUI

struct PlaylistView: View {
    @State private var selectedTags: Set<String> = []
    let allTags: [String] = ["#chill", "#late", "#unreleased", "#favorite"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Master Playlist")
                .font(.title2)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.9))
            
            TagBarView(selectedTags: $selectedTags, allTags: allTags, onPresetTap: {
                // TODO: Show preset picker
            }, onPresetLongPress: {
                // TODO: Show name input for saving preset
            })
            .background(Color.black.opacity(0.9))
            
            List {
                // Placeholder song rows
                ForEach(0..<20) { index in
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Song \(index + 1)")
                                .foregroundColor(.white)
                            Text("Artist Name")
                                .font(.caption)
                                .foregroundColor(Color.gray.opacity(0.7))
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.black.opacity(0.8))
                }
            }
            .listStyle(PlainListStyle())
            .background(Color.black.opacity(0.9))
        }
        .background(Color.black.edgesIgnoringSafeArea(.all))
    }
}

struct PlaylistView_Previews: PreviewProvider {
    static var previews: some View {
        PlaylistView()
            .background(Color.black)
    }
}
