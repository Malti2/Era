import UIKit
import UniformTypeIdentifiers

// Share Extension (Spec 8: Share Sheet als Import-Weg).
// Eingeschraenkt bei unsigniertem Sideloading: App Groups brauchen Provisioning.
// Mit App Group landen die Dateien in der Inbox der App, ohne zeigt die
// Extension einen Hinweis. Details: DECISIONS.md.
final class ShareViewController: UIViewController {

    private let groupID = "group.de.malte.era"
    private let label = UILabel()
    private let activity = UIActivityIndicatorView(style: .medium)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body)
        label.translatesAutoresizingMaskIntoConstraints = false
        activity.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        view.addSubview(activity)
        NSLayoutConstraint.activate([
            activity.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activity.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            label.topAnchor.constraint(equalTo: activity.bottomAnchor, constant: 16)
        ])
        handleSharedItems()
    }

    private func handleSharedItems() {
        activity.startAnimating()
        label.text = "Speichere in Era …"
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { finish(); return }
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            label.text = "Era öffnen und dort importieren.\n(Share Extension braucht eine signierte Installation mit App Groups.)"
            activity.stopAnimating()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.cancel() }
            return
        }
        let inbox = group.appendingPathComponent("Inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)

        let providers = items.compactMap(\.attachments).flatMap { $0 }
        guard !providers.isEmpty else { finish(); return }
        var remaining = providers.count
        for provider in providers {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.audio.identifier) { url, _ in
                if let url {
                    let dest = inbox.appendingPathComponent(url.lastPathComponent)
                    try? FileManager.default.copyItem(at: url, to: dest)
                }
                DispatchQueue.main.async {
                    remaining -= 1
                    if remaining == 0 {
                        self.activity.stopAnimating()
                        self.label.text = "In Era abgelegt"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.finish() }
                    }
                }
            }
        }
    }

    private func finish() { extensionContext?.completeRequest(returningItems: nil) }
    private func cancel() { extensionContext?.cancelRequest(withError: NSError(domain: "EraShare", code: 0)) }
}
