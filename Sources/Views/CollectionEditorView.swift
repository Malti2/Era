import SwiftUI
import SwiftData

// Sammlung anlegen oder bearbeiten: Name plus Status/Tags, die ein Song alle haben muss.
// Die Trefferzahl aktualisiert sich live, damit man sieht, was die Regel faengt.
struct CollectionEditorView: View {
    /// nil = neue Sammlung
    let pack: Pack?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: EraStore
    @Query(sort: \Tag.name) private var tags: [Tag]
    @Query private var songs: [Song]
    @Query private var packs: [Pack]

    @State private var name = ""
    @State private var rule = CollectionRule()

    private var statusTags: [Tag] { tags.filter { $0.isStatus && !$0.songs.isEmpty || rule.statusNames.contains($0.name) } }
    private var personalTags: [Tag] {
        tags.filter { !$0.isStatus }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private var matchCount: Int { songs.filter { $0.matches(rule) }.count }
    private var otherNames: [String] { packs.filter { $0.id != pack?.id }.map(\.name) }
    private var nameCheck: CollectionName.Check { CollectionName.validate(name, existing: otherNames) }
    private var canSave: Bool {
        if case .ok = nameCheck { return !rule.isEmpty }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                } footer: {
                    if nameCheck == .duplicate { Text("A collection with this name already exists.").foregroundStyle(.red) }
                }
                if !statusTags.isEmpty {
                    Section("Status") {
                        ForEach(statusTags) { tag in
                            Toggle(tag.name, isOn: Binding(get: { rule.statusNames.contains(tag.name) }, set: { _ in rule.toggle(status: tag.name) }))
                        }
                    }
                }
                Section("Tags") {
                    if personalTags.isEmpty {
                        Text("Add tags to songs first, then use them here.").foregroundStyle(.secondary)
                    }
                    ForEach(personalTags) { tag in
                        Toggle(tag.name, isOn: Binding(get: { rule.tagIDs.contains(tag.id) }, set: { _ in rule.toggle(tag: tag.id) }))
                    }
                }
                Section {
                    Label(rule.isEmpty ? String(localized: "Choose at least one status or tag.") : String(localized: "\(matchCount) songs match"),
                          systemImage: rule.isEmpty ? "hand.point.up.left" : "music.note.list")
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("A song must have all chosen statuses and tags.")
                }
            }
            .navigationTitle(pack == nil ? "New Collection" : "Edit Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave).fontWeight(.semibold)
                }
            }
            .onAppear {
                if let pack, name.isEmpty {
                    name = pack.name
                    rule = pack.rule
                }
            }
        }
    }

    private func save() {
        if let pack {
            if store.updateCollection(pack, name: name, rule: rule) { dismiss() }
        } else if store.createCollection(named: name, rule: rule) != nil {
            dismiss()
        }
    }
}
