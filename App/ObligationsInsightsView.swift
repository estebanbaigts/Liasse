import SwiftUI
import CockpitCore

struct ObligationsView: View {
    @Environment(AppModel.self) private var model
    @State private var year = Calendar.fr.component(.year, from: Date())
    @State private var selected: Obligation?

    var body: some View {
        let fin = model.finance
        let cash = fin.cashPosition()
        let supported = model.ledger.profile.legalForm.isAutomaticallySupported
        let obligations = fin.tax.obligations(year: year, today: model.today)
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                if !supported {
                    Label("Ta forme juridique (\(model.ledger.profile.legalForm.label)) n'est pas calculée automatiquement : ses cotisations et impôts dépendent de paramètres que seul un expert-comptable peut établir. Tu peux saisir les montants déclarés et payés manuellement plus tard.", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .top, spacing: DS.Space.xxl) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack { Text("À garder de côté").font(.callout).foregroundStyle(.secondary); EstimateBadge() }
                        Amount(money: cash.reservesOutstanding, font: DS.Font.figureLarge, color: DS.reserve)
                        Text("Obligations nées, pas encore payées").font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Sur ton compte").font(.callout).foregroundStyle(.secondary)
                        Amount(money: cash.balance, font: DS.Font.figureLarge)
                        Text("Libre après réserves : \(cash.free)").font(.caption).foregroundStyle(cash.free.isNegative ? DS.outflow : .secondary)
                    }
                    Spacer()
                }
                Text("Les réserves sont des affectations virtuelles : elles ne sortent de ton compte que lorsque tu paies réellement l'URSSAF ou les impôts. Une estimation n'est jamais un montant réclamé par l'administration.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

                let alerts = fin.tax.thresholdAlerts(year: year, today: model.today)
                ForEach(alerts, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(DS.reserve) }

                VStack(alignment: .leading, spacing: 0) {
                    SectionTitle("Échéances \(String(year))", trailing: AnyView(Stepper("", value: $year, in: 2020...2100).labelsHidden()))
                    if obligations.isEmpty { Text("Aucune obligation calculée pour cette année.").foregroundStyle(.secondary).padding(.vertical, 8) }
                    ForEach(obligations) { o in
                        Button { selected = o } label: {
                            HStack(spacing: DS.Space.m) {
                                IconBubble(symbol: o.kind.symbol, tint: o.status.color == .secondary ? DS.reserve : o.status.color, size: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(fin.tax.label(o)).fontWeight(.semibold).lineLimit(1)
                                    Text(["Échéance \(o.dueDate.long)", o.base.flatMap { o.kind == .cfe ? nil : "base \($0)" }].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .layoutPriority(1)
                                Spacer(minLength: DS.Space.s)
                                VStack(alignment: .trailing, spacing: 2) {
                                    if let paid = o.record?.paidAmount {
                                        Amount(money: paid, font: .body.weight(.semibold), color: DS.income)
                                        Text("payé").font(.caption).foregroundStyle(.secondary)
                                    } else if let declared = o.record?.declaredAmount {
                                        Amount(money: declared, font: .body.weight(.semibold))
                                        Text("déclaré · estimé \(o.estimated?.description ?? "—")").font(.caption).foregroundStyle(.secondary)
                                    } else if let est = o.estimated {
                                        Amount(money: est, font: .body.weight(.semibold), color: .secondary)
                                        Text("estimé").font(.caption).foregroundStyle(.secondary)
                                    } else {
                                        Text("—").foregroundStyle(.secondary)
                                        Text("montant à vérifier").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .fixedSize()
                                StatusTag(text: o.status.label, color: o.status.color, symbol: o.status.symbol).fixedSize()
                            }
                            .padding(.vertical, 8).padding(.horizontal, 6)
                            .overlay(alignment: .bottom) { Rectangle().fill(DS.hairline).frame(height: 1) }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(DS.Space.page)
            .frame(maxWidth: 1100, alignment: .leading)
        }
        .navigationTitle("Réserves & impôts")
        .sheet(item: $selected) { ObligationDetail(obligation: $0) }
    }
}

struct ObligationDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let obligation: Obligation
    @State private var declared: Money = .zero
    @State private var hasDeclared = false
    @State private var paid: Money = .zero
    @State private var hasPaid = false
    @State private var paidDate = Date()
    @State private var note = ""

    var body: some View {
        let o = obligation
        VStack(alignment: .leading, spacing: DS.Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text(o.kind.label).font(.title3.weight(.semibold))
                Spacer()
                StatusTag(text: o.status.label, color: o.status.color)
            }
            Text("Échéance : \(o.dueDate.long)").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text("Calcul").font(.headline); EstimateBadge() }
                Text(o.explanation).fixedSize(horizontal: false, vertical: true)
                if let r = o.rule {
                    Text("Règle : \(r.key.label) — \(r.formattedValue), \(r.nature.label.lowercased()). Base : \(r.base). Effective depuis le \(r.effectiveFrom.long). Vérifiée le \(r.verifiedOn.long) sur \(r.sourceName) (\(r.confidence.label.lowercased())).")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let url = URL(string: r.sourceURL) { Link("Ouvrir la source officielle", destination: url).font(.caption) }
                }
                ForEach(o.warnings, id: \.self) { Label($0, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            Divider()
            Form {
                Toggle("J'ai déclaré ce montant", isOn: $hasDeclared)
                if hasDeclared { LabeledContent("Montant déclaré") { MoneyField(title: "Déclaré", value: $declared).frame(width: 130) } }
                Toggle("J'ai payé", isOn: $hasPaid)
                if hasPaid {
                    LabeledContent("Montant payé") { MoneyField(title: "Payé", value: $paid).frame(width: 130) }
                    DatePicker("Date du paiement", selection: $paidDate, displayedComponents: .date)
                }
                TextField("Note", text: $note)
                if hasDeclared, let e = o.estimated {
                    let v = declared - e
                    Text(v.isZero ? "Conforme à l'estimation." : "Écart avec l'estimation : \(v.isPositive ? "+" : "")\(v)").font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .frame(height: 250)
            HStack {
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Enregistrer") {
                    var r = o.record ?? ObligationRecord(key: o.key)
                    r.declaredAmount = hasDeclared ? declared : nil
                    r.declaredDate = hasDeclared ? (r.declaredDate ?? model.today) : nil
                    r.paidAmount = hasPaid ? paid : nil
                    r.paidDate = hasPaid ? paidDate : nil
                    r.note = note
                    model.update("Obligation mise à jour.") { $0.updateObligationRecord(r) }
                    dismiss()
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(DS.Space.l).frame(width: 520)
        .onAppear {
            let r = o.record
            hasDeclared = r?.declaredAmount != nil; declared = r?.declaredAmount ?? o.estimated ?? .zero
            hasPaid = r?.paidAmount != nil; paid = r?.paidAmount ?? r?.declaredAmount ?? o.estimated ?? .zero
            paidDate = r?.paidDate ?? model.today; note = r?.note ?? ""
        }
    }
}

struct InsightsView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let items = model.insights
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Calculées sur ce Mac à partir de tes données. Aucune donnée n'est envoyée à un service externe.")
                    .font(.callout).foregroundStyle(.secondary).padding(.bottom, DS.Space.l)
                if items.isEmpty {
                    EmptyState(symbol: "checkmark.seal", title: "Rien à signaler", message: "Pas de retard, de risque de trésorerie ni de seuil à surveiller pour l'instant.").frame(height: 300)
                }
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in InsightRow(insight: item).appear(i) }
            }
            .padding(DS.Space.page)
            .frame(maxWidth: 860, alignment: .leading)
        }
        .navigationTitle("Conseils")
    }
}

struct InsightRow: View {
    @Environment(AppModel.self) private var model
    let insight: Insight
    @State private var expanded = false

    var tint: Color { insight.urgency >= 3 ? DS.outflow : (insight.urgency == 2 ? DS.reserve : (insight.urgency == 1 ? DS.due : Color.teal)) }
    var symbol: String {
        switch insight.target {
        case .invoices, .invoice: "envelope.badge.fill"; case .forecast: "chart.line.downtrend.xyaxis"; case .obligations: "lock.shield.fill"
        case .missions: "target"; case .expenses: "cart.fill"; case .clients: "person.2.fill"; case .settings: "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        Card(tint: tint) {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                HStack(alignment: .top, spacing: DS.Space.m) {
                    IconBubble(symbol: symbol, tint: tint, size: 40, filled: true)
                        .symbolEffect(.bounce, options: .nonRepeating, value: expanded)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(insight.title).font(.headline)
                            if insight.urgency >= 3 { StatusTag(text: "urgent", color: DS.outflow, symbol: "flame.fill") }
                        }
                        Text(insight.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button(insight.actionLabel) { go(insight.target) }.buttonStyle(.borderedProminent).tint(tint)
                        .accessibilityLabel(insight.urgency >= 3 ? "Urgent : \(insight.actionLabel)" : insight.actionLabel)
                }
                if expanded {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(insight.figures, id: \.label) { f in HStack { Text(f.label); Spacer(); Text(f.value).monospacedDigit().fontWeight(.semibold) }.font(.callout) }
                        Text("Période : \(insight.period) · \(insight.reliability.label)").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                        ForEach(insight.assumptions, id: \.self) { Text("Hypothèse : \($0)").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                    }
                    .padding(.leading, 52)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                Button { expanded.toggle() } label: {
                    Label(expanded ? "Masquer le détail" : "Chiffres et hypothèses", systemImage: expanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.link).font(.caption).padding(.leading, 52)
            }
        }
        .hoverLift()
        .padding(.bottom, DS.Space.m)
        .dsAnimation(expanded)
    }

    func go(_ t: InsightTarget) {
        switch t {
        case .invoices(let overdue): model.invoiceFilter = overdue ? .overdue : .all; model.screen = .invoices
        case .invoice(let id): model.selectedInvoice = id; model.screen = .invoices
        case .expenses: model.screen = .expenses
        case .obligations: model.screen = .obligations
        case .forecast: model.screen = .forecast
        case .clients: model.screen = .clients
        case .missions: model.screen = .missions
        case .settings: model.screen = .settings
        }
    }
}
