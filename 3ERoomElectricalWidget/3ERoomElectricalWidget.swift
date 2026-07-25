import SwiftUI
import WidgetKit

private let widgetKind = "3ERoomElectricalSideloadTest"

private struct StaticWidgetEntry: TimelineEntry {
    let date: Date
}

private struct StaticWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> StaticWidgetEntry {
        StaticWidgetEntry(date: Date())
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (StaticWidgetEntry) -> Void
    ) {
        completion(StaticWidgetEntry(date: Date()))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<StaticWidgetEntry>) -> Void
    ) {
        completion(
            Timeline(
                entries: [StaticWidgetEntry(date: Date())],
                policy: .never
            )
        )
    }
}

private struct StaticWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.025, green: 0.055, blue: 0.11),
                    Color(red: 0.02, green: 0.18, blue: 0.25)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: family == .systemSmall ? 8 : 12) {
                Image(systemName: "viewfinder.rectangular")
                    .font(.system(size: family == .systemSmall ? 34 : 42,
                                  weight: .bold))
                    .foregroundStyle(.cyan)

                Text("3E Room Electrical")
                    .font(family == .systemSmall ? .headline : .title3.bold())
                    .multilineTextAlignment(.center)

                Text("WidgetKit Test • Build 21")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.72))

                if family != .systemSmall {
                    Text("اضغط لفتح التطبيق")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.62))
                }
            }
            .foregroundStyle(.white)
            .padding()
        }
        .environment(\.layoutDirection, .rightToLeft)
        .widgetURL(URL(string: "3eroomelectrical://projects"))
        .containerBackground(for: .widget) {
            Color(red: 0.025, green: 0.055, blue: 0.11)
        }
    }
}

@main
struct ThreeERoomElectricalStaticWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: widgetKind,
            provider: StaticWidgetProvider()
        ) { _ in
            StaticWidgetView()
        }
        .configurationDisplayName("3E Room Electrical")
        .description("ويدجت اختبار ثابتة متوافقة مع التوقيع الجانبي.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
