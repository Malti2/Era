import SwiftUI
import UniformTypeIdentifiers

// UIKit-Document-Picker statt SwiftUI .fileImporter:
// .fileImporter schliesst auf echten iPhones den Picker nach "Öffnen" nicht und
// ruft den Completion-Handler nie auf (bekannter iOS-Bug, im Simulator unsichtbar).
// UIDocumentPickerViewController funktioniert auf Geraeten nachweislich zuverlaessig.
//
// asCopy: true = Import-Modus: iOS kopiert die Auswahl in ein app-eigenes
// Temp-Verzeichnis. Die URLs gehoeren der App, es ist kein
// Security-Scoped-Resource-Zugriff noetig - das umgeht zusaetzlich die
// iOS-26-Regression "You do not have permission to view the file" beim
// Lesen security-scoped URLs.
struct DocumentPicker: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let onPicked: ([URL]) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPicked: ([URL]) -> Void
        let onCancel: () -> Void

        init(onPicked: @escaping ([URL]) -> Void, onCancel: @escaping () -> Void) {
            self.onPicked = onPicked
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPicked(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}
