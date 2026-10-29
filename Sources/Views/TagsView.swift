import SwiftUI
import SwiftData

// Tag-Verwaltung: umbenennen (gleicher Name = zusammenfuehren), loeschen, Ungenutztes aufraeumen.
struct TagsView: View {
    @EnvironmentObject private var store: EraStore
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @State private var renaming: Tag?
    @State private var draftName = ""
    @State private var mergeRequest: MergeRequest?
    @State private var tagToDelete: Tag?
    @State private var confirmUnused = false

    private struct MergeRequest: Identifiable {
        let id = UUID()
        let tag: Tag
        let name: String
        let target: String
    }

    private var tags: [Tag] {
        allTags.filter { !$0.isStatus }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private var unusedCount: Int { store.unusedTags().count }

    var body: some View {
        List {
            if tags.isEmpty {
                ContentUnavailableView {
                    Label("No Tags Yet", systemImage: "tag")
                } description: {
                    Text("Add tags to songs from their details. They show up here for renaming and cleanup.")
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(tags) { tag in
                        Button {
                            draftName = tag.name
                            renaming = tag
                        } label: {
                            HStack {
                                Label(tag.name, systemImage: "tag").foregroundStyle(.primary)
                                Spacer()
                                Text("\(tag.songs.count)").foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) { tagToDelete = tag } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                } footer: {
                    Text("Tap a tag to rename it. Using the name of another tag combines both.")
                }
                if unusedCount > 0 {
                    Section {
                        Button(role: .destructive) { confirmUnused = true } label: {
                            Label(String(format: String(localized: "Remove %lld Unused Tags"), unusedCount), systemImage: "wand.and.sparkles")
                        }
                    } footer: {
                        Text("Unused tags are not on any song and not part of a collection.")
                    }
                }
            }
        }
        .navigationTitle("Tags")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Rename Tag", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $draftName)
            Button("Rename") { submitRename() }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("Combine Tags?", isPresented: Binding(get: { mergeRequest != nil }, set: { if !$0 { mergeRequest = nil } }), titleVisibility: .visible) {
            if let request = mergeRequest {
                Button("Combine into “\(request.target)”") {
                    store.renameTag(request.tag, to: request.name)
                    mergeRequest = nil
                }
            }
            Button("Cancel", role: .cancel) { mergeRequest = nil }
        } message: {
            if let request = mergeRequest {
                Text("“\(request.tag.name)” and “\(request.target)” become one tag on all their songs.")
            }
        }
        .confirmationDialog("Delete Tag?", isPresented: Binding(get: { tagToDelete != nil }, set: { if !$0 { tagToDelete = nil } }), titleVisibility: .visible) {
            Button("Delete Tag", role: .destructive) {
                if let tag = tagToDelete { store.deleteTagEverywhere(tag) }
                tagToDelete = nil
            }
            Button("Cancel", role: .cancel) { tagToDelete = nil }
        } message: {
            Text("The tag is removed from all songs. The songs stay in your library.")
        }
        .confirmationDialog("Remove Unused Tags?", isPresented: $confirmUnused, titleVisibility: .visible) {
            Button("Remove Unused Tags", role: .destructive) { store.deleteUnusedTags() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func submitRename() {
        guard let tag = renaming else { return }
        renaming = nil
        let names = allTags.map(\.name)
        switch TagRename.resolve(draftName, current: tag.name, existing: names) {
        case .merge(let target): mergeRequest = MergeRequest(tag: tag, name: draftName, target: target)
        case .rename: store.renameTag(tag, to: draftName)
        case .invalid, .unchanged: break
        }
    }
}
