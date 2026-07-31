import SwiftUI

struct ThreeEStorageSettingsSection: View {
    @ObservedObject var storage: ThreeEStorageManager
    let chooseFolder: () -> Void

    var body: some View {
        Section("مجموعة تطبيقات 3E") {
            Label(
                storage.statusMessage,
                systemImage: storage.isSharedFolderConnected
                    ? "folder.badge.checkmark"
                    : "folder.badge.plus"
            )
            .foregroundStyle(
                storage.isSharedFolderConnected ? Color.green : Color.orange
            )

            LabeledContent("مصدر التخزين", value: storage.source.title)
            LabeledContent(
                "المجلد المختار",
                value: storage.selectedFolderName
            )
            LabeledContent(
                "مجلد التطبيق",
                value: ThreeEStorageConstants.appRelativePath
            )
            LabeledContent(
                "App Key",
                value: ThreeEStorageConstants.appKey
            )
            LabeledContent(
                "URL Scheme",
                value: "electrical://"
            )

            Button(action: chooseFolder) {
                Label(
                    storage.isSharedFolderConnected
                        ? "إعادة اختيار مجلد 3E"
                        : "اختيار مجلد 3E من Files",
                    systemImage: "folder"
                )
            }
            .disabled(storage.source == .appGroup)

            Text(
                "لا يعتمد التطبيق على App Group أثناء التوقيع المجاني. "
                    + "المعرف المستقبلي الجاهز هو "
                    + ThreeEStorageConstants.futureAppGroupIdentifier
                    + "."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
