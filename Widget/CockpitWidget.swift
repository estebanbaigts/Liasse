import WidgetKit
import SwiftUI
import AppIntents
import CockpitCore

struct CockpitWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Liasse"
    static let description = IntentDescription("Ton argent disponible, tes réserves et tes échéances.")
    @Parameter(title: "Masquer les montants", default: false) var hideAmounts: Bool
    @Parameter(title: "Afficher l'évolution récente", default: true) var showTrend: Bool
    init() {}
}

struct Entry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let hide: Bool
    let showTrend: Bool
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, snapshot: .placeholder, hide: false, showTrend: true) }
    func snapshot(for c: CockpitWidgetIntent, in context: Context) async -> Entry {
        Entry(date: .now, snapshot: context.isPreview ? .placeholder : SharedSnapshot.read(), hide: c.hideAmounts, showTrend: c.showTrend)
    }
    /// L'app recharge les timelines après chaque modification ; à défaut, rafraîchissement horaire
    /// (dans la limite du budget accordé par le système). La date de calcul est toujours affichée.
    func timeline(for c: CockpitWidgetIntent, in context: Context) async -> Timeline<Entry> {
        let e = Entry(date: .now, snapshot: SharedSnapshot.read(), hide: c.hideAmounts, showTrend: c.showTrend)
        return Timeline(entries: [e], policy: .after(.now.addingTimeInterval(3600)))
    }
}

struct CockpitWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: Entry
    var body: some View {
        CockpitWidgetContent(size: family == .systemSmall ? .small : (family == .systemMedium ? .medium : .large),
                             snapshot: entry.snapshot, hide: entry.hide, showTrend: entry.showTrend)
    }
}

struct CockpitWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "CockpitWidget", intent: CockpitWidgetIntent.self, provider: Provider()) { entry in
            CockpitWidgetView(entry: entry)
                .fontDesign(.rounded)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [WColor.brand.opacity(0.18), WColor.income.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
        }
        .configurationDisplayName("Liasse")
        .description("Argent disponible, réserves, factures en attente et échéances.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct CockpitWidgetBundle: WidgetBundle {
    var body: some Widget { CockpitWidget() }
}
