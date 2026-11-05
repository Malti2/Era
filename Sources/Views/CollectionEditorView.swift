import SwiftUI
import SwiftData

// Sammlung anlegen oder bearbeiten: Name plus Status/Tags, die ein Song alle haben muss.
// Die Trefferzahl aktualisiert sich live, damit man sieht, was die Regel faengt.
struct CollectionEditorView: View {
    /// nil = neue Sammlung
    let pack: Pack?
    /// Vorbelegung der gespeicherten Suche (z. B. aus der Suche heraus).
    var initialQuery = ""
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
                if rule.needsMatchMode {
                    Section {
                        Picker("Match", selection: $rule.matchAny) {
                            Text("All").tag(false)
                            Text("Any").tag(true)
                        }
                        .pickerStyle(.segmented)
                    } footer: {
                        Text(rule.matchAny ? "A song needs at least one of the chosen statuses or tags." : "A song needs all of the chosen statuses and tags.")
                    }
                }
                Section {
                    TextField("era:synth plays:0 -tag:demo", text: $rule.query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                } header: {
                    Text("Saved Search")
                } footer: {
                    Text("Optional. Uses the same words and filters as Search, e.g. has:notes or year:2018-2020. Songs must match this as well.")
                }
                if !statusTags.isEmpty {
                    Section("Status") {
                        ForEach(statusTags) { tag in
                            markRow(tag.name, mark: rule.mark(status: tag.name)) { rule.cycle(status: tag.name) }
                        }
                    }
                }
                Section {
                    if personalTags.isEmpty {
                        Text("Add tags to songs first, then use them here.").foregroundStyle(.secondary)
                    }
                    ForEach(personalTags) { tag in
                        markRow(tag.name, mark: rule.mark(tag: tag.id)) { rule.cycle(tag: tag.id) }
                    }
                } header: {
                    Text("Tags")
                } footer: {
                    Text("Tap once to include, twice to exclude, a third time to clear.")
                }
                Section {
                    Label(rule.isEmpty ? String(localized: "Choose at least one status, tag or search.") : String(localized: "\(matchCount) songs match"),
                          systemImage: rule.isEmpty ? "hand.point.up.left" : "music.note.list")
                        .foregroundStyle(.secondary)
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
                    rule = pack.rule.pruned(toExistingTagIDs: Set(tags.map(\.id)))
                } else if pack == nil, rule.query.isEmpty, !initialQuery.isEmpty {
                    rule.query = initialQuery
                }
            }
        }
    }

    /// Dreistufige Zeile: aus / dabei (Haken) / ohne (rotes Minus). Der Zustand steht auch als Text im Accessibility-Wert.
    private func markRow(_ title: String, mark: CollectionRule.Mark, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(mark == .exclude ? Color.secondary : Color.primary)
                    .strikethrough(mark == .exclude)
                Spacer()
                switch mark {
                case .none: EmptyView()
                case .include: Image(systemName: "checkmark").foregroundStyle(.tint)
                case .exclude: Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(mark == .include ? Text("Included") : (mark == .exclude ? Text("Excluded") : Text("Off")))
    }

    private func save() {
        if let pack {
            if store.updateCollection(pack, name: name, rule: rule) { dismiss() }
        } else if store.createCollection(named: name, rule: rule) != nil {
            dismiss()
        }
    }
}
