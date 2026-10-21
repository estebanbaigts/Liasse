import SwiftUI
import WidgetKit
import CockpitCore

enum WColor {
    static let income = Color(light: .init(red: 14/255, green: 150/255, blue: 104/255), dark: .init(red: 52/255, green: 211/255, blue: 153/255))
    static let reserve = Color(light: .init(red: 214/255, green: 104/255, blue: 0), dark: .init(red: 1, green: 166/255, blue: 61/255))
    static let brand = Color(light: .init(red: 124/255, green: 77/255, blue: 1), dark: .init(red: 146/255, green: 110/255, blue: 1))
    static let outflow = Color(light: .init(red: 222/255, green: 56/255, blue: 74/255), dark: .init(red: 1, green: 107/255, blue: 122/255))
}

extension Color {
    init(light: Color, dark: Color) {
        self = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light) })
    }
}

struct M: View {
    let money: Money
    let hide: Bool
    var font: Font = .body
    var color: Color = .primary
    var body: some View {
        Text(hide ? "•••• €" : MoneyFormat.string(money, showCents: false))
            .font(font.monospacedDigit()).fontDesign(.rounded).foregroundStyle(color).minimumScaleFactor(0.6).lineLimit(1)
            .privacySensitive()
    }
}

struct Caption: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View { Text(text).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
}

enum WidgetSize: String, CaseIterable, Identifiable { case small, medium, large; var id: String { rawValue } }

/// Vues du widget, partagées avec l'app (aperçu dans les réglages).
struct CockpitWidgetContent: View {
    let size: WidgetSize
    let snapshot: WidgetSnapshot?
    let hide: Bool
    let showTrend: Bool
    var entry: (snapshot: WidgetSnapshot?, hide: Bool, showTrend: Bool) { (snapshot, hide, showTrend) }

    var body: some View {
        if let s = snapshot {
            switch size {
            case .small: small(s)
            case .medium: medium(s)
            case .large: large(s)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "eurosign.circle").font(.title2).foregroundStyle(.secondary)
                Text("Ouvre Cockpit").font(.headline)
                Text("Le résumé apparaîtra après le premier enregistrement.").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(URL(string: "cockpit://today"))
        }
    }

    func updated(_ s: WidgetSnapshot) -> some View {
        Caption("Calculé \(s.generatedAt.formatted(.relative(presentation: .named).locale(Locale(identifier: "fr_FR"))))")
    }

    func small(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: "eurosign.circle.fill").foregroundStyle(WColor.income)
                Caption("Disponible · \(s.monthLabel.lowercased())")
            }
            M(money: s.available, hide: entry.hide, font: .system(size: 24, weight: .semibold), color: s.available.isNegative ? WColor.outflow : WColor.income)
            Spacer(minLength: 6)
            Caption("À réserver")
            M(money: s.toReserve, hide: entry.hide, font: .system(size: 15, weight: .semibold), color: WColor.reserve)
            Spacer(minLength: 6)
            if let n = s.nextDeadline {
                let days = Calendar.fr.dateComponents([.day], from: Calendar.fr.startOfDay(for: .now), to: Calendar.fr.startOfDay(for: n.date)).day ?? 0
                Label("\(n.title.components(separatedBy: " · ").first ?? n.title) \(days <= 0 ? "aujourd'hui" : "dans \(days) j")", systemImage: n.isAlert ? "exclamationmark.circle.fill" : "calendar")
                    .font(.caption2).foregroundStyle(n.isAlert ? WColor.reserve : .secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "cockpit://today"))
    }

    func medium(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                GridRow {
                    WLink(destination: URL(string: "cockpit://today")!) {
                        VStack(alignment: .leading, spacing: 1) { Caption("Encaissé · \(s.monthLabel.lowercased())"); M(money: s.collectedMonth, hide: entry.hide, font: .system(size: 19, weight: .semibold)) }
                    }
                    WLink(destination: URL(string: "cockpit://obligations")!) {
                        VStack(alignment: .leading, spacing: 1) { Caption("Réserves estimées"); M(money: s.toReserve, hide: entry.hide, font: .system(size: 19, weight: .semibold), color: WColor.reserve) }
                    }
                }
                GridRow {
                    WLink(destination: URL(string: "cockpit://invoices?filter=unpaid")!) {
                        VStack(alignment: .leading, spacing: 1) {
                            Caption("Impayées")
                            HStack(spacing: 4) {
                                M(money: s.receivables, hide: entry.hide, font: .system(size: 14, weight: .semibold))
                                if s.overdueCount > 0 { Text("· \(s.overdueCount) en retard").font(.caption2).foregroundStyle(WColor.outflow) }
                            }
                        }
                    }
                    WLink(destination: URL(string: "cockpit://obligations")!) {
                        VStack(alignment: .leading, spacing: 1) {
                            Caption("Prochaine échéance")
                            Text(s.nextDeadline.map { "\($0.date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_FR")))) · \($0.title)" } ?? "Aucune").font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            updated(s)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    func large(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            WLink(destination: URL(string: "cockpit://today")!) {
                VStack(alignment: .leading, spacing: 1) {
                    Caption("Trésorerie")
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        M(money: s.cashBalance, hide: entry.hide, font: .system(size: 22, weight: .semibold))
                        if !entry.hide { Text("dont \(MoneyFormat.string(s.available, showCents: false)) libres ce mois").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }
                }
            }
            if entry.showTrend && !entry.hide && s.recentBalances.count > 1 {
                WLink(destination: URL(string: "cockpit://forecast")!) { Trend(values: s.recentBalances).frame(height: 44) }
                    .accessibilityLabel("Évolution du solde sur 30 jours")
            }
            Caption("Prochaines échéances")
            ForEach(s.deadlines.prefix(3)) { d in
                WLink(destination: URL(string: "cockpit://obligations")!) {
                    HStack {
                        Text("\(d.title) · \(d.date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_FR"))))").font(.caption).foregroundStyle(d.isAlert ? WColor.reserve : .primary).lineLimit(1)
                        Spacer()
                        M(money: d.amount, hide: entry.hide, font: .caption)
                    }
                }
            }
            if s.deadlines.isEmpty { Text("Aucune dans les 90 jours").font(.caption).foregroundStyle(.secondary) }
            Caption("En attente de paiement")
            ForEach(s.pendingInvoices.prefix(3)) { i in
                WLink(destination: URL(string: "cockpit://invoices?id=\(i.id)")!) {
                    HStack {
                        Text(i.title + (i.isAlert ? " · retard" : "")).font(.caption).foregroundStyle(i.isAlert ? WColor.outflow : .primary).lineLimit(1)
                        Spacer()
                        M(money: i.amount, hide: entry.hide, font: .caption)
                    }
                }
            }
            if s.pendingInvoices.isEmpty { Text("Aucune facture en attente").font(.caption).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
            updated(s)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct Trend: View {
    let values: [Money]
    var body: some View {
        GeometryReader { g in
            let v = values.map { Double($0.cents) }
            let lo = v.min() ?? 0, hi = max(v.max() ?? 1, lo + 1)
            Path { p in
                for (i, x) in v.enumerated() {
                    let pt = CGPoint(x: g.size.width * CGFloat(i) / CGFloat(max(v.count - 1, 1)), y: g.size.height * (1 - CGFloat((x - lo) / (hi - lo))))
                    i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                }
            }
            .stroke(LinearGradient(colors: [WColor.brand, WColor.income], startPoint: .leading, endPoint: .trailing), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
    }
}


/// Lien sans teinte d'accent : les couleurs sémantiques restent lisibles.
struct WLink<Label: View>: View {
    let destination: URL
    @ViewBuilder var label: () -> Label
    init(destination: URL, @ViewBuilder label: @escaping () -> Label) { self.destination = destination; self.label = label }
    var body: some View { Link(destination: destination, label: label).buttonStyle(.plain) }
}
