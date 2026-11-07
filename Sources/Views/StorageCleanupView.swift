import SwiftUI

// Library Overview -> Free Up Space: alternative Versionen nach Groesse, gesammelt loeschen.
struct StorageCleanupView: View {
    let items: [StorageItem]
    var onDeleted: () -> Void = {}

    @EnvironmentObject private var store: EraStore
    @Environment(\.dismiss) private var dismiss
    @State private var selection = Set<UUID>()
    @State private var confirm = false
    @State private var removedCount = 0

    @State private var removed = Set<UUID>()
    private var cleanup: StorageCleanup { StorageCleanup.make(from: items.filter { !removed.contains($0.id) }) }

    private let bigThreshold: Int64 = 20_000_000

    private func sizeText(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    var body: some View {
        let cleanup = cleanup
        List {
            if cleanup.isEmpty {
                ContentUnavailableView {
                    Label("Nothing to Clean Up", systemImage: "checkmark.circle")
                } description: {
                    Text(removedCount > 0 ? "Removed \(removedCount) versions." : "Your songs have no alternate versions.")
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(cleanup.candidates) { item in
                        Button { toggle(item.id) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selection.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selection.contains(item.id) ? Color.accentColor : Color.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).lineLimit(1)
                                    Text(item.versionName).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(sizeText(item.bytes ?? 0)).foregroundStyle(.secondary).monospacedDigit()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selection.contains(item.id) ? .isSelected : [])
                    }
                } header: {
                    Text("\(cleanup.candidates.count) alternate versions")
                } footer: {
                    Text("Main versions are never listed. Deleted files cannot be restored, back up first if unsure.")
                }
            }
        }
        .navigationTitle("Free Up Space")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !cleanup.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Select All") { selection = Set(cleanup.candidates.map(\.id)) }
                        if !cleanup.ids(atLeast: bigThreshold).isEmpty {
                            Button("Select Large Files") { selection = cleanup.ids(atLeast: bigThreshold) }
                        }
                        Button("Select None") { selection = [] }.disabled(selection.isEmpty)
                    } label: { Label("Select", systemImage: "checklist") }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !selection.isEmpty {
                Button(role: .destructive) { confirm = true } label: {
                    Text("Delete \(selection.count) · \(sizeText(cleanup.bytes(of: selection)))")
                        .font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
                .padding().background(.bar)
            }
        }
        .confirmationDialog("Delete Versions?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Delete \(selection.count) Versions", role: .destructive) { deleteSelected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The audio files of the selected versions are removed from this device. The songs stay in your library.")
        }
    }

    private func toggle(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    private func deleteSelected() {
        let ids = selection
        let count = store.deleteAlternateVersions(ids: ids)
        removed.formUnion(ids)
        removedCount += count
        selection = []
        onDeleted()
    }
}
