import SwiftUI
import SwiftData

// Tags fuer mehrere Songs auf einmal: Haken = alle, Strich = einige, leer = keiner.
struct BulkTagSheet: View {
    let songs: [Song]
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: EraStore
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @State private var newTag = ""

    private var statusTags: [Tag] { allTags.filter(\.isStatus) }
    private var personalTags: [Tag] {
        allTags.filter { !$0.isStatus }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func coverage(_ tag: Tag) -> TagCoverage {
        BulkTagging.coverage(of: tag.name, in: songs.map { $0.tags.map(\.name) })
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("New Tag", text: $newTag).onSubmit(addNew)
                        Button(action: addNew) { Image(systemName: "plus.circle.fill") }
                            .disabled(BulkTagging.cleanName(newTag) == nil)
                            .accessibilityLabel("Add Tag")
                    }
                } header: {
                    Text(String(format: String(localized: "Tags for %lld songs"), songs.count))
                }
                if !personalTags.isEmpty { Section("Tags") { ForEach(personalTags) { row($0) } } }
                Section("Status") { ForEach(statusTags) { row($0) } }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ tag: Tag) -> some View {
        let state = coverage(tag)
        return Button {
            if BulkTagging.shouldAdd(state) { store.add(tag, to: songs) } else { store.remove(tag, from: songs) }
        } label: {
            HStack {
                Text(tag.name).foregroundStyle(.primary)
                Spacer()
                switch state {
                case .all: Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                case .some: Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                case .none: Image(systemName: "circle").foregroundStyle(.tertiary)
                }
            }
        }
        .accessibilityValue(state == .all ? Text("On all songs") : state == .some ? Text("On some songs") : Text("On no songs"))
    }

    private func addNew() {
        guard let name = BulkTagging.cleanName(newTag) else { return }
        store.add(store.makeTag(named: name), to: songs)
        newTag = ""
    }
}
