import SwiftUI

// Update drawer shown at launch when GitHub has a newer release: icon, name,
// current -> latest version, with direct IPA download and an AltStore source link.
struct UpdatePromptView: View {
    let currentVersion: String
    let release: UpdateService.Release
    @ObservedObject var updater: UpdateService
    @Environment(\.dismiss) private var dismiss
    @State private var shareItem: ShareItem?
    private let altStoreSourceURL = URL(string: "https://altdirect.app/?url=https%3A%2F%2Fmalti2.github.io%2FEra%2Fsource.json")!

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            Image(uiImage: AppIconImage.uiImage)
                .resizable()
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text("Era").font(.title2.weight(.semibold))
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(currentVersion)
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.right")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(release.version)
                    .foregroundStyle(.green)
                    .fontWeight(.bold)
            }
            .font(.title2)
            Text("A new version of Era is available.")
                .font(.subheadline).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(release.notes.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.prefix(3), id: \.self) { note in
                    Label(String(note).trimmingCharacters(in: CharacterSet(charactersIn: "-• ")), systemImage: "checkmark")
                }
            }.font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            updateArea
            Button("Later") {
                UserDefaults.standard.set(release.version, forKey: "updates.snoozedVersion")
                dismiss()
            }
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding()
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isBusy)
        .sheet(item: $shareItem) { item in ShareSheet(items: [item.url]) }
        .onChange(of: updater.state) { _, state in
            if case .downloaded(_, let url) = state { shareItem = ShareItem(url: url) }
        }
    }

    private var isBusy: Bool {
        if case .downloading = updater.state { return true }
        return false
    }

    @ViewBuilder
    private var updateArea: some View {
        switch updater.state {
        case .downloading:
            VStack(spacing: 8) {
                ProgressView()
                Text("Downloading…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(height: 44)
        case .downloaded:
            Label("Downloaded - use the share sheet to open it in your sideloading app.", systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.green)
                .multilineTextAlignment(.center)
                .frame(height: 44)
        case .failed(let message):
            VStack(spacing: 8) {
                Text(message).font(.footnote).foregroundStyle(.red)
                Button("Try Again") { Task { await updater.download(release) } }
            }
            .frame(height: 44)
        default:
            VStack(spacing: 10) {
                Button {
                    Task { await updater.download(release) }
                } label: {
                    Label("Download IPA", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .eraProminentButton()
                .controlSize(.large)

                Link(destination: altStoreSourceURL) {
                    Label("Add AltStore Source", systemImage: "plus.app.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }
}
