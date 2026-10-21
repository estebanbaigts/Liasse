import SwiftUI
import Charts
import CockpitCore

/// Prévisions — direction 4 « La ligne du temps ».
struct ForecastView: View {
    @Environment(AppModel.self) private var model
    @State private var horizon = 90
    @State private var focus: Scenario = .realistic
    @State private var editing = false

    struct Pt: Identifiable { let id = UUID(); let date: Date; let value: Double; let scenario: Scenario }

    var body: some View {
        let fe = model.forecast
        let results = Scenario.allCases.map { fe.run($0, days: horizon) }
        let main = results.first { $0.scenario == focus }!
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                HStackOrVStack {
                    figure("Aujourd'hui sur le compte", "building.columns.fill", DS.due, main.start, nil, nil)
                    figure("Point bas (\(focus.label.lowercased()))", "arrow.down.to.line", main.low.balance < fe.assumptions.safetyThreshold ? DS.outflow : DS.reserve, main.low.balance, main.low.balance < fe.assumptions.safetyThreshold ? DS.outflow : DS.reserve, main.low.date.long)
                    figure("Dans \(horizon) jours", "flag.checkered", DS.income, main.balance(at: horizon), nil, nil)
                }
                .appear(0)
                if let below = main.firstBelowThreshold {
                    Label("En scénario \(focus.label.lowercased()), ta trésorerie passe sous \(fe.assumptions.safetyThreshold) le \(below.long).", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(DS.outflow)
                }
                Card { VStack(alignment: .leading, spacing: DS.Space.m) { chart(results, focus: main); legend } }.appear(1)
                Text(main.assumptions.joined(separator: " ")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                events(main)
            }
            .padding(DS.Space.page)
            .frame(maxWidth: 1100, alignment: .leading)
        }
        .navigationTitle("Prévisions")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Horizon", selection: $horizon) { Text("30 j").tag(30); Text("60 j").tag(60); Text("90 j").tag(90) }
                    .pickerStyle(.segmented).fixedSize()
            }
            ToolbarItem {
                Button { editing = true } label: { Label("Hypothèses", systemImage: "slider.horizontal.3") }
                    .popover(isPresented: $editing) { AssumptionsEditor().padding().frame(width: 360) }
            }
        }
    }

    func figure(_ label: String, _ symbol: String, _ tint: Color, _ m: Money, _ color: Color?, _ sub: String?) -> some View {
        Card(tint: tint, padding: DS.Space.m + 4) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: DS.Space.s) { IconBubble(symbol: symbol, tint: tint, size: 28, filled: true); Text(label).font(.callout.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1) }
                Amount(money: m, font: DS.Font.figure, color: color).lineLimit(1).minimumScaleFactor(0.7)
                Text(sub ?? " ").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    func chart(_ results: [ForecastResult], focus: ForecastResult) -> some View {
        let pts = results.flatMap { r in r.points.map { Pt(date: $0.date, value: NSDecimalNumber(decimal: $0.balance.decimal).doubleValue, scenario: r.scenario) } }
        let threshold = NSDecimalNumber(decimal: model.forecastAssumptions.safetyThreshold.decimal).doubleValue
        // Un repère par jour : les obligations d'une même échéance sont regroupées (URSSAF + CFP…).
        let relevant = focus.events.filter { $0.kind == .obligation || $0.kind == .reserveOnInflow || ($0.kind == .expense && $0.amount.cents <= -20000) }
        let marks: [ForecastEvent] = Dictionary(grouping: relevant) { Calendar.fr.startOfDay(for: $0.date) }.map { day, evs in
            let names = Array(NSOrderedSet(array: evs.map { $0.label.components(separatedBy: " · ").first ?? $0.label })) as? [String] ?? []
            return ForecastEvent(date: day, label: names.prefix(2).joined(separator: " + ") + (names.count > 2 ? "…" : ""), amount: evs.sum(\.amount),
                                 kind: evs.contains { $0.kind != .expense } ? .obligation : .expense, note: "")
        }.sorted { $0.date < $1.date }
        // Échelle resserrée sur les soldes ; le seuil n'élargit l'axe que s'il est proche.
        let values = pts.map(\.value)
        var lo = values.min() ?? 0, hi = values.max() ?? 1
        let pad = max((hi - lo) * 0.25, 500)
        if threshold >= lo - 2 * pad { lo = min(lo, threshold); hi = max(hi, threshold) }
        let focusPts = pts.filter { $0.scenario == self.focus }
        let focusColor: Color = self.focus == .optimistic ? .secondary : (self.focus == .realistic ? DS.brandA : DS.reserve)
        return Chart {
            ForEach(focusPts) { p in
                AreaMark(x: .value("Date", p.date), yStart: .value("Base", lo - pad), yEnd: .value("Solde", p.value))
                    .interpolationMethod(.stepStart)
                    .foregroundStyle(LinearGradient(colors: [focusColor.opacity(0.35), focusColor.opacity(0.02)], startPoint: .top, endPoint: .bottom))
            }
            ForEach(pts) { p in
                LineMark(x: .value("Date", p.date), y: .value("Solde", p.value), series: .value("Scénario", p.scenario.label))
                    .interpolationMethod(.stepStart)
                    .foregroundStyle(by: .value("Scénario", p.scenario.label))
                    .lineStyle(StrokeStyle(lineWidth: p.scenario == self.focus ? 2.5 : 1.3, dash: p.scenario == .realistic ? [] : (p.scenario == .optimistic ? [4, 4] : [2, 3])))
            }
            if threshold >= lo - pad { RuleMark(y: .value("Seuil", threshold)).foregroundStyle(DS.outflow.opacity(0.35)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4])) }
            ForEach(marks) { e in
                PointMark(x: .value("Date", e.date), y: .value("Solde", NSDecimalNumber(decimal: (focus.points.first { Calendar.fr.isDate($0.date, inSameDayAs: e.date) }?.balance ?? .zero).decimal).doubleValue))
                    .foregroundStyle(e.kind == .expense ? DS.due : DS.reserve)
                    .symbolSize(40)
                    .annotation(position: .bottom, alignment: .leading, spacing: 4) {
                        Text("\(e.label) · \(e.date.short)").font(.caption2).foregroundStyle(e.kind == .expense ? DS.due : DS.reserve).fixedSize()
                    }
            }
            PointMark(x: .value("Date", focus.low.date), y: .value("Solde", NSDecimalNumber(decimal: focus.low.balance.decimal).doubleValue))
                .symbol(.diamond).symbolSize(70).foregroundStyle(.primary)
        }
        .chartForegroundStyleScale(["Optimiste": Color.secondary, "Réaliste": DS.brandA, "Prudent": DS.reserve])
        .chartLegend(.hidden)
        .chartYScale(domain: (lo - pad)...(hi + pad))
        .chartXAxis { AxisMarks(values: .stride(by: .day, count: horizon <= 30 ? 7 : 15)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
        .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let d = v.as(Double.self) { Text(Money(decimalEuros: Decimal(d)).formattedShort) } } } }
        .frame(height: 320)
        .accessibilityLabel("Trésorerie projetée sur \(horizon) jours, trois scénarios. Point bas \(focus.low.balance.description) le \(focus.low.date.long).")
    }

    var legend: some View {
        HStack(spacing: DS.Space.l) {
            ForEach(Scenario.allCases) { s in
                Button { focus = s } label: {
                    HStack(spacing: 6) {
                        Capsule().fill(s == .optimistic ? Color.secondary : (s == .realistic ? DS.brandA : DS.reserve)).frame(width: 18, height: 5)
                        Text(s.label).fontWeight(s == focus ? .semibold : .regular)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(s == focus ? .isSelected : [])
            }
            Spacer()
            Button("Modifier les hypothèses") { editing = true }.buttonStyle(.link)
        }
        .font(.callout)
    }

    func events(_ r: ForecastResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Mouvements pris en compte (\(r.scenario.label.lowercased()))")
            if r.events.isEmpty { Text("Aucun mouvement prévu sur la période.").foregroundStyle(.secondary).padding(.vertical, 8) }
            ForEach(r.events) { e in
                LedgerRow(title: e.label, subtitle: "\(e.date.long) · \(e.note)",
                          symbol: e.amount.isNegative ? (e.kind == .expense ? "cart.fill" : "lock.shield.fill") : (e.kind == .plannedWork ? "briefcase.fill" : "arrow.down.circle.fill"),
                          tint: e.amount.isNegative ? (e.kind == .expense ? DS.outflow : DS.reserve) : DS.income) {
                    Amount(money: e.amount, color: e.amount.isNegative ? nil : DS.income, signed: true).frame(minWidth: 110, alignment: .trailing)
                }
            }
        }
    }
}

struct AssumptionsEditor: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        let observed = model.forecast.observedDelay()
        Form {
            Section("Scénario réaliste") {
                Toggle("Utiliser le retard moyen observé (\(observed) j)", isOn: Binding(
                    get: { model.forecastAssumptions.realisticDelayDays == nil },
                    set: { model.forecastAssumptions.realisticDelayDays = $0 ? nil : observed }))
                if let d = model.forecastAssumptions.realisticDelayDays {
                    Stepper("Retard supposé : \(d) j", value: Binding(get: { d }, set: { model.forecastAssumptions.realisticDelayDays = $0 }), in: 0...120)
                }
                Stepper("Exclure après \(model.forecastAssumptions.realisticOverdueCutoffDays) j de retard", value: $model.forecastAssumptions.realisticOverdueCutoffDays, in: 15...365, step: 15)
            }
            Section("Scénario prudent") {
                Stepper("Retard supplémentaire : \(model.forecastAssumptions.prudentExtraDelayDays) j", value: $model.forecastAssumptions.prudentExtraDelayDays, in: 0...120, step: 5)
            }
            Section("Optimiste") { Toggle("Inclure le travail prévu non facturé", isOn: $model.forecastAssumptions.includeUninvoicedMissions) }
            Section("Alerte") { LabeledContent("Seuil de trésorerie") { MoneyField(title: "Seuil", value: $model.forecastAssumptions.safetyThreshold).frame(width: 120) } }
        }
        .formStyle(.grouped)
    }
}
