import SwiftUI

// Update drawer shown at launch when GitHub has a newer release: icon, name,
// current -> latest version, one Update button that downloads the IPA and
// hands it to the share sheet (AltStore/SideStore sideload flow).
struct UpdatePromptView: View {
    let currentVersion: String
    let release: UpdateService.Release
    @ObservedObject var updater: UpdateService
    @Environment(\.dismiss) private var dismiss
    @State private var shareItem: ShareItem?

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
                .font(.subheadline)
                .foregroundStyle(.secondary)
            updateArea
            Button("Later") { dismiss() }
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
            Button {
                Task { await updater.download(release) }
            } label: {
                Label("Update", systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .eraProminentButton()
            .controlSize(.large)
        }
    }
}
