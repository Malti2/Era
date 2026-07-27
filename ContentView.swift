import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationView {
            PlaylistView()
                .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .background(Color.black.edgesIgnoringSafeArea(.all))
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .background(Color.black)
    }
}
