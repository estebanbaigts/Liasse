import SwiftUI
import Charts
import CockpitCore

struct TraceRequest: Identifiable {
    let id = UUID()
    let title: String
    let explanation: String
    let items: [TraceItem]
    let total: Money
}

/// Accueil — « La phrase », version vivante : salutation, carte héros animée, tuiles de l'équation.
struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @State private var trace: TraceRequest?

    var body: some View {
        let fin = model.finance
        let dash = fin.dashboard(period: model.period)
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                header.appear(0)
                if model.ledger.invoices.isEmpty && model.ledger.expenses.isEmpty {
                    emptyHero.appear(1)
                } else {
                    hero(dash).appear(1)
                    equation(dash).appear(2)
                    cashCard(dash).appear(3)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: DS.Space.l) {
                        receivables(dash).frame(minWidth: 330, maxWidth: .infinity, alignment: .topLeading)
                        deadlines(dash).frame(minWidth: 330, maxWidth: .infinity, alignment: .topLeading)
                    }
                    VStack(alignment: .leading, spacing: DS.Space.l) { receivables(dash); deadlines(dash) }
                }
                .appear(4)
                trend.appear(5)
            }
            .padding(DS.Space.page)
            .frame(maxWidth: 1040, alignment: .leading)
            .dsAnimation(dash.available)
        }
        .navigationTitle("Aujourd'hui")
        .toolbar { PeriodToolbar(); ToolbarItem { Button { model.requestNew(.invoices) } label: { Label("Nouvelle facture", systemImage: "plus") } } }
        .sheet(item: $trace) { TraceSheet(request: $0) }
    }

    var periodPhrase: String {
        switch model.periodChoice {
        case .month: "ce mois-ci"; case .quarter: "ce trimestre"; case .year: "cette année"; case .custom: "sur la période"
        }
    }

    var timeSymbol: String {
        let h = Calendar.fr.component(.hour, from: Date())
        return h < 7 ? "moon.stars.fill" : (h < 12 ? "sunrise.fill" : (h < 19 ? "sun.max.fill" : "moon.fill"))
    }

    var header: some View {
        HStack(alignment: .center, spacing: DS.Space.m) {
            Image(systemName: timeSymbol)
                .font(.system(size: 30))
                .symbolRenderingMode(.multicolor)
                .symbolEffect(.bounce, options: .nonRepeating, value: model.screen)
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting(for: Date(), name: model.ledger.profile.ownerName)).font(.system(size: 28, weight: .heavy, design: .rounded))
                Text(model.today.weekdayLong).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    var emptyHero: some View {
        ZStack(alignment: .leading) {
            LivelyBackground(colors: [DS.brandA, DS.brandB, DS.brandA, DS.brandB, DS.brandC, DS.brandB, DS.brandC, DS.brandA, DS.brandC])
            VStack(alignment: .leading, spacing: DS.Space.m) {
                Image(systemName: "sparkles").font(.system(size: 34)).symbolEffect(.pulse)
                Text("On démarre ? Crée ta première facture ou enregistre une dépense.").font(DS.Font.sentence).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button { model.requestNew(.invoices) } label: { Label("Créer une facture", systemImage: "plus.circle.fill") }
                        .buttonStyle(.borderedProminent).tint(.white.opacity(0.25))
                    Button("Importer un relevé CSV") { model.screen = .importBank }.buttonStyle(.bordered).tint(.white)
                    Button("Voir avec des données d'exemple") { model.loadSample() }.buttonStyle(.plain).underline()
                }
                .controlSize(.large)
            }
            .foregroundStyle(.white)
            .padding(DS.Space.xl)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
    }

    func heroColors(_ d: Dashboard) -> [Color] {
        if d.available.isNegative { return [DS.outflow, DS.brandB, DS.outflow, DS.brandB, DS.reserve, DS.brandB, DS.reserve, DS.outflow, DS.brandC] }
        return [DS.income, .teal, DS.due, .teal, DS.income, DS.brandA, DS.due, .teal, DS.income]
    }

    func hero(_ d: Dashboard) -> some View {
        let goal = model.ledger.profile.monthlyRevenueGoal
        let invoicedMonth = model.finance.invoiced(in: .month(of: model.today)).0
        let progress = goal.isPositive ? NSDecimalNumber(decimal: invoicedMonth.decimal / goal.decimal).doubleValue : 0
        return ZStack {
            LivelyBackground(colors: heroColors(d))
            HStack(alignment: .center, spacing: DS.Space.xl) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(d.available.isNegative ? "Attention, \(periodPhrase) tu es à découvert de" : "Tu peux utiliser")
                        .font(.title3.weight(.semibold)).opacity(0.9)
                    CountingAmount(money: d.available.isNegative ? -d.available : d.available, font: DS.Font.hero, color: .white)
                    Text(d.available.isNegative ? "une fois tes dépenses et tes réserves prises en compte." : "\(periodPhrase), une fois tes réserves mises de côté.")
                        .font(.title3.weight(.medium)).opacity(0.9)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                if goal.isPositive && model.periodChoice == .month {
                    VStack(spacing: 6) {
                        ZStack {
                            ProgressRing(progress: progress, tint: .white, lineWidth: 9).frame(width: 92, height: 92)
                            Text(MoneyFormat.percent(Decimal(min(progress, 9.99)), digits: 0)).font(.system(size: 20, weight: .heavy, design: .rounded))
                        }
                        Text("de ton objectif").font(.caption.weight(.semibold)).opacity(0.85)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Objectif du mois : \(MoneyFormat.percent(Decimal(progress), digits: 0)) facturés")
                    .help("Facturé HT ce mois-ci : \(invoicedMonth) sur un objectif de \(goal)")
                }
            }
            .foregroundStyle(.white)
            .padding(DS.Space.xl)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .shadow(color: (d.available.isNegative ? DS.outflow : DS.income).opacity(0.3), radius: 18, y: 8)
    }

    func equation(_ d: Dashboard) -> some View {
        let tiles = HStackOrVStack {
            tile("Encaissé", "arrow.down.circle.fill", d.collected, DS.income, sign: "+", delta: PeriodComparison.delta(d.collected, d.previous.collected)) {
                trace = TraceRequest(title: "Encaissé", explanation: "Paiements réellement reçus sur la période. Les factures non payées n'y figurent jamais.", items: d.collectedTrace, total: d.collected)
            }
            tile("Dépenses payées", "cart.fill", d.expensesPaid, DS.outflow, sign: "−", delta: nil) {
                trace = TraceRequest(title: "Dépenses payées", explanation: "Dépenses marquées payées sur la période. Les dépenses prévues sont suivies à part.", items: d.expensesPaidTrace, total: d.expensesPaid)
            }
            tile("À réserver", "lock.shield.fill", d.reserves.total, DS.reserve, sign: "−", delta: nil, estimate: true) {
                var items: [TraceItem] = []
                let date = d.period.start
                if d.reserves.cotisations.isPositive { items.append(TraceItem(date: date, label: "Cotisations URSSAF", amount: d.reserves.cotisations, source: .opening)) }
                if d.reserves.cfp.isPositive { items.append(TraceItem(date: date, label: "Formation professionnelle", amount: d.reserves.cfp, source: .opening)) }
                if d.reserves.incomeTax.isPositive { items.append(TraceItem(date: date, label: model.ledger.profile.versementLiberatoire ? "Versement libératoire" : "Impôt sur le revenu (estimation)", amount: d.reserves.incomeTax, source: .opening)) }
                if d.reserves.vat.isPositive { items.append(TraceItem(date: date, label: "TVA collectée", amount: d.reserves.vat, source: .opening)) }
                trace = TraceRequest(title: "À réserver", explanation: "Calculé sur \(d.reserves.collectedHT) encaissés HT.\n" + d.reserves.assumptions.joined(separator: "\n"), items: items, total: d.reserves.total)
            }
        }
        return VStack(alignment: .leading, spacing: DS.Space.s) {
            tiles
            Text(contextLine(d)).font(.callout).foregroundStyle(.secondary).padding(.leading, 4)
        }
    }

    func tile(_ label: String, _ symbol: String, _ m: Money, _ tint: Color, sign: String, delta: Decimal?, estimate: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Card(tint: tint, padding: DS.Space.m + 4) {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    HStack(spacing: DS.Space.s) {
                        IconBubble(symbol: symbol, tint: tint, size: 30, filled: true)
                        Text(label).font(.callout.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 0)
                        if estimate { EstimateBadge(text: "estim.") }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(sign).font(DS.Font.figure).foregroundStyle(tint)
                        Amount(money: m, font: DS.Font.figure).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    if let delta {
                        Label("\(delta >= 0 ? "+" : "")\(MoneyFormat.percent(delta, digits: 0)) vs avant", systemImage: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption.weight(.semibold)).foregroundStyle(delta >= 0 ? DS.income : DS.outflow)
                            .help("Par rapport à la période précédente de même durée")
                    } else {
                        Text("Voir le détail").font(.caption.weight(.medium)).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .hoverLift()
        .help("Voir les opérations qui composent ce montant")
        .accessibilityHint("Affiche les transactions sources")
    }

    func contextLine(_ d: Dashboard) -> String {
        var parts = ["\(d.invoicedHT) facturés HT"]
        if d.receivables.isPositive { parts.append("\(d.receivables) pas encore payés au total") }
        if d.expensesPlanned.isPositive { parts.append("\(d.expensesPlanned) de dépenses prévues") }
        return parts.joined(separator: " · ")
    }

    func cashCard(_ d: Dashboard) -> some View {
        let total = max(d.cash.balance.decimal, 1)
        let reserveShare = min(max(NSDecimalNumber(decimal: d.cash.reservesOutstanding.decimal / total).doubleValue, 0), 1)
        return Button {
            trace = TraceRequest(title: "Solde du compte", explanation: "Solde de départ saisi + encaissements − dépenses payées − obligations payées. Recale-le de temps en temps avec ton relevé (Réglages › Profil).",
                                 items: d.cash.balanceTrace, total: d.cash.balance)
        } label: {
            Card(padding: DS.Space.m + 4) {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    HStack(spacing: DS.Space.s) {
                        IconBubble(symbol: "building.columns.fill", tint: DS.due, size: 30, filled: true)
                        Text("Sur ton compte").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                        Amount(money: d.cash.balance, font: DS.Font.figure)
                        Spacer()
                        Text("dont \(d.cash.reservesOutstanding) à garder · \(d.cash.free) libres").font(.callout).foregroundStyle(.secondary)
                    }
                    GeometryReader { g in
                        HStack(spacing: 3) {
                            Capsule().fill(DS.reserve.gradient).frame(width: max(6, g.size.width * reserveShare))
                            Capsule().fill(DS.income.gradient)
                        }
                    }
                    .frame(height: 10)
                    .accessibilityLabel("Part du solde à réserver : \(MoneyFormat.percent(Decimal(reserveShare), digits: 0))")
                }
            }
        }
        .buttonStyle(.plain)
        .hoverLift()
        .help("Voir comment ce solde est reconstitué")
    }

    func receivables(_ d: Dashboard) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                SectionTitle("On te doit", trailing: d.receivableInvoices.isEmpty ? nil : AnyView(Button("Tout voir") { model.invoiceFilter = .unpaid; model.screen = .invoices }.buttonStyle(.link)))
                if d.receivableInvoices.isEmpty {
                    Label("Tout le monde t'a payé.", systemImage: "hands.clap.fill").foregroundStyle(.secondary).padding(.vertical, 8)
                }
                ForEach(d.receivableInvoices.prefix(5)) { inv in
                    let late = inv.status(on: model.today) == .overdue
                    let days = Calendar.fr.dateComponents([.day], from: Calendar.fr.startOfDay(for: model.today), to: Calendar.fr.startOfDay(for: inv.dueDate)).day ?? 0
                    Button { model.invoiceFilter = .all; model.selectedInvoice = inv.id; model.screen = .invoices } label: {
                        HStack(spacing: DS.Space.m) {
                            Avatar(name: model.finance.clientName(inv), size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.finance.clientName(inv)).fontWeight(.semibold).lineLimit(1)
                                Text(inv.number ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: DS.Space.s)
                            if late { StatusTag(text: "retard \(inv.daysLate(on: model.today)) j", color: DS.outflow, symbol: "exclamationmark") }
                            else { StatusTag(text: days == 0 ? "aujourd'hui" : "dans \(days) j", color: DS.due, symbol: "clock") }
                            Amount(money: inv.balance, font: .body.weight(.semibold)).frame(minWidth: 90, alignment: .trailing)
                        }
                        .padding(.vertical, 6).padding(.horizontal, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverLift()
                }
            }
        }
    }

    func deadlines(_ d: Dashboard) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                SectionTitle("Prochaines échéances", trailing: AnyView(Button("Réserves & impôts") { model.screen = .obligations }.buttonStyle(.link)))
                let items = d.upcoming.prefix(5)
                if items.isEmpty { Label("Rien de prévu dans les 90 prochains jours.", systemImage: "beach.umbrella.fill").foregroundStyle(.secondary).padding(.vertical, 8) }
                ForEach(Array(items)) { item in
                    let days = Calendar.fr.dateComponents([.day], from: Calendar.fr.startOfDay(for: model.today), to: Calendar.fr.startOfDay(for: item.date)).day ?? 0
                    HStack(spacing: DS.Space.m) {
                        switch item.kind {
                        case .obligation(let k, _): IconBubble(symbol: k.symbol, tint: DS.reserve, size: 32)
                        default: IconBubble(symbol: "calendar", tint: DS.due, size: 32)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).fontWeight(.semibold).lineLimit(1)
                            Text("\(item.date.long) · \(item.detail)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: DS.Space.s)
                        if case .obligation(_, .toVerify) = item.kind {
                            StatusTag(text: "à vérifier", color: DS.reserve, symbol: "questionmark")
                        } else {
                            StatusTag(text: days < 0 ? "dépassée" : (days == 0 ? "aujourd'hui" : "J-\(days)"), color: days <= 14 ? DS.reserve : .secondary)
                            if item.isEstimate, case .obligation = item.kind { EstimateBadge(text: "estim.") }
                            Amount(money: item.amount, font: .body.weight(.semibold)).frame(minWidth: 80, alignment: .trailing)
                        }
                    }
                    .padding(.vertical, 6).padding(.horizontal, 6)
                }
            }
        }
    }

    struct MonthPoint: Identifiable { let id = UUID(); let month: Date; let kind: String; let amount: Double }

    var trend: some View {
        let fin = model.finance
        let cal = Calendar.fr
        let months: [Date] = (0..<6).reversed().map { cal.date(byAdding: .month, value: -$0, to: cal.startOfMonth(model.today))! }
        let points = months.flatMap { m -> [MonthPoint] in
            let p = Period.month(of: m)
            return [MonthPoint(month: m, kind: "Encaissé", amount: NSDecimalNumber(decimal: fin.collected(in: p).0.decimal).doubleValue),
                    MonthPoint(month: m, kind: "Dépenses payées", amount: NSDecimalNumber(decimal: fin.expensesPaid(in: p).0.decimal).doubleValue)]
        }
        return Card {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                SectionTitle("Six derniers mois")
                Chart(points) { p in
                    BarMark(x: .value("Mois", p.month, unit: .month), y: .value("Montant", p.amount))
                        .foregroundStyle(by: .value("Type", p.kind))
                        .position(by: .value("Type", p.kind))
                        .cornerRadius(6)
                }
                .chartForegroundStyleScale(["Encaissé": DS.income.gradient, "Dépenses payées": DS.outflow.gradient])
                .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                .chartYAxis { AxisMarks { v in AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3])); AxisValueLabel { if let d = v.as(Double.self) { Text(Money(decimalEuros: Decimal(d)).formattedShort) } } } }
                .frame(height: 180)
                .accessibilityLabel("Encaissements et dépenses payées des six derniers mois")
            }
        }
    }
}

/// Aligne horizontalement, ou verticalement quand la place manque.
struct HStackOrVStack<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DS.Space.m) { content() }.frame(minWidth: 540)
            VStack(alignment: .leading, spacing: DS.Space.m) { content() }
        }
    }
}


extension Money {
    var formattedShort: String { MoneyFormat.string(self, showCents: false) }
}

struct PeriodToolbar: ToolbarContent {
    @Environment(AppModel.self) private var model
    var body: some ToolbarContent {
        @Bindable var model = model
        ToolbarItem(placement: .principal) {
            HStack {
                Picker("Période", selection: $model.periodChoice) {
                    ForEach(PeriodChoice.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                if model.periodChoice == .custom {
                    DatePicker("Du", selection: $model.customPeriod.start, displayedComponents: .date).labelsHidden()
                    DatePicker("au", selection: $model.customPeriod.end, in: model.customPeriod.start..., displayedComponents: .date).labelsHidden()
                }
            }
        }
    }
}

struct TraceSheet: View {
    let request: TraceRequest
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text(request.title).font(.title2.weight(.semibold))
                Spacer()
                Amount(money: request.total, font: DS.Font.figure)
            }
            Text(request.explanation).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if request.items.isEmpty {
                Text("Aucune opération sur cette période.").foregroundStyle(.secondary).padding(.vertical)
            } else {
                Table(request.items) {
                    TableColumn("Date") { Text($0.date.short) }.width(80)
                    TableColumn("Origine") { Text($0.label) }
                    TableColumn("Montant") { Amount(money: $0.amount).frame(maxWidth: .infinity, alignment: .trailing) }.width(110)
                }
                .frame(minHeight: 220)
                HStack { Text("Total des \(request.items.count) lignes"); Spacer(); Amount(money: request.items.sum(\.amount)).bold() }
                    .font(.callout)
            }
            HStack { Spacer(); Button("Fermer") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(DS.Space.l)
        .frame(width: 560)
    }
}
