import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ThreeEFolderPicker: UIViewControllerRepresentable {
    let completion: (Result<URL, Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    func makeUIViewController(
        context: Context
    ) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.folder],
            asCopy: false
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let completion: (Result<URL, Error>) -> Void

        init(completion: @escaping (Result<URL, Error>) -> Void) {
            self.completion = completion
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            guard let url = urls.first else {
                completion(.failure(ThreeEStorageError.invalidRelativePath))
                return
            }
            completion(.success(url))
        }

        func documentPickerWasCancelled(
            _ controller: UIDocumentPickerViewController
        ) {
            completion(.failure(CancellationError()))
        }
    }
}
