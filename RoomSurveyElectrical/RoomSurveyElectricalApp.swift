import SwiftUI

@main
struct RoomSurveyElectricalApp: App {
    init() {
        try? ApplicationFileLayout.prepare()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.layoutDirection, .rightToLeft)
        }
    }
}
