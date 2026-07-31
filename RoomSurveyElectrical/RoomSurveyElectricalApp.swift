import SwiftUI

@main
struct RoomSurveyElectricalApp: App {
    init() {
        try? ThreeEStorageManager.shared.ensureDirectories()
        try? ApplicationFileLayout.prepare()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.layoutDirection, .rightToLeft)
        }
    }
}
