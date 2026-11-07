import SwiftUI

// Operator-Hilfe: Beispiele antippen, um sie direkt zu suchen.
struct SearchHelpView: View {
    var onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Type words to search titles, artists, albums, tags and notes. Add filters to narrow things down. Tap an example to try it.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(SearchHelp.groups) { group in
                    Section(LocalizedStringKey(group.title)) {
                        ForEach(group.entries) { entry in
                            Button {
                                onPick(entry.example)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.example)
                                        .font(.system(.subheadline, design: .monospaced).weight(.medium))
                                        .foregroundStyle(.tint)
                                    Text(LocalizedStringKey(entry.title)).font(.footnote).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                            .accessibilityHint(Text("Searches for this example"))
                        }
                    }
                }
            }
            .navigationTitle("Search Tips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}
