import Foundation

public enum Reliability: String, Sendable, CaseIterable {
    case high, medium, low
    public var label: String { switch self { case .high: "Fiabilité élevée"; case .medium: "Fiabilité moyenne"; case .low: "Fiabilité faible" } }
}

public enum InsightTarget: Hashable, Sendable { case invoices(overdueOnly: Bool), invoice(UUID), expenses, obligations, forecast, clients, missions, settings }

/// Une recommandation chiffrée, vérifiable, calculée localement.
public struct Insight: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var figures: [Figure]
    public var period: String
    public var assumptions: [String]
    public var reliability: Reliability
    /// Impact financier estimé (valeur absolue) pour le classement.
    public var impact: Money
    /// 3 = urgent, 0 = information.
    public var urgency: Int
    public var target: InsightTarget
    public var actionLabel: String

    public struct Figure: Hashable, Sendable { public var label: String; public var value: String }
}

public struct InsightEngine: Sendable {
    public let finance: FinanceEngine
    public let forecast: ForecastEngine
    public init(finance: FinanceEngine, forecast: ForecastEngine) { self.finance = finance; self.forecast = forecast }

    public func insights() -> [Insight] {
        var out: [Insight] = []
        let cal = finance.calendar, today = finance.today
        let month = Period.month(of: today, calendar: cal)
        let fmtDate: (Date) -> String = { $0.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_FR"))) }

        // 1. Factures en retard
        let late = finance.overdueInvoices
        if !late.isEmpty {
            let total = late.sum(\.balance)
            let oldest = late.map { $0.daysLate(on: today, calendar: cal) }.max() ?? 0
            out.append(Insight(id: "overdue", title: late.count == 1 ? "Une facture est en retard" : "\(late.count) factures sont en retard",
                               detail: "Leur solde total est de \(total). La plus ancienne a \(oldest) jours de retard. Une relance rapide améliore nettement les chances d'être payé.",
                               figures: late.prefix(4).map { .init(label: "\(finance.clientName($0)) · \($0.number ?? "")", value: "\($0.balance) · \($0.daysLate(on: today, calendar: cal)) j") },
                               period: "À date du \(fmtDate(today))", assumptions: ["Retard = jours écoulés depuis l'échéance indiquée sur la facture."],
                               reliability: .high, impact: total, urgency: oldest > 30 ? 3 : 2, target: .invoices(overdueOnly: true), actionLabel: "Préparer les relances"))
        }

        // 2. Risque de manque de trésorerie à la prochaine échéance (scénario prudent)
        let prudent = forecast.run(.prudent)
        let nextDue = finance.upcoming().first { if case .obligation = $0.kind { return $0.amount.isPositive } else { return false } }
        if prudent.low.balance < forecast.assumptions.safetyThreshold {
            let gap = forecast.assumptions.safetyThreshold - prudent.low.balance
            out.append(Insight(id: "shortfall", title: "Tu pourrais manquer de \(gap) d'ici 90 jours",
                               detail: "En scénario prudent, ta trésorerie descend à \(prudent.low.balance) le \(fmtDate(prudent.low.date)).",
                               figures: [.init(label: "Solde actuel", value: prudent.start.description), .init(label: "Point bas prudent", value: prudent.low.balance.description)] +
                                (nextDue.map { [.init(label: "Prochaine échéance", value: "\($0.title) · \($0.amount)")] } ?? []),
                               period: "90 prochains jours", assumptions: prudent.assumptions, reliability: .medium,
                               impact: gap, urgency: 3, target: .forecast, actionLabel: "Voir la prévision"))
        } else if let next = nextDue {
            let free = finance.cashPosition()
            if free.balance < next.amount {
                out.append(Insight(id: "nextdue", title: "Ton solde ne couvre pas la prochaine échéance",
                                   detail: "\(next.title) : \(next.amount) le \(fmtDate(next.date)), pour un solde de \(free.balance).",
                                   figures: [.init(label: "Échéance", value: next.amount.description), .init(label: "Solde", value: free.balance.description)],
                                   period: "Prochaine échéance", assumptions: ["Montant \(next.isEstimate ? "estimé" : "déclaré")."], reliability: next.isEstimate ? .medium : .high,
                                   impact: next.amount - free.balance, urgency: 3, target: .obligations, actionLabel: "Voir les obligations"))
            }
        }

        // 3. Réserve recommandée
        let cash = finance.cashPosition()
        if cash.reservesOutstanding.isPositive {
            let byKind = Dictionary(grouping: cash.reserveObligations, by: \.kind).map { ($0.key, $0.value.sum(\.remaining)) }.sorted { $0.1 > $1.1 }
            out.append(Insight(id: "reserve", title: "Garde \(cash.reservesOutstanding) de côté",
                               detail: "C'est ce que représentent tes obligations déjà nées et non payées, d'après tes encaissements et ton profil.",
                               figures: byKind.map { .init(label: $0.0.shortLabel, value: $0.1.description) },
                               period: "Périodes en cours et passées non payées",
                               assumptions: ["Montants déclarés quand tu les as saisis, sinon estimés avec les règles du catalogue."],
                               reliability: cash.reserveObligations.contains { $0.status == .toVerify } ? .low : .medium,
                               impact: cash.reservesOutstanding, urgency: 1, target: .obligations, actionLabel: "Voir le détail"))
        }

        // 4. Objectif mensuel
        let goal = finance.ledger.profile.monthlyRevenueGoal
        if goal.isPositive {
            let invoiced = finance.invoiced(in: month).0
            let tjm = finance.averageDailyRate()
            if invoiced < goal && tjm.isPositive {
                let missing = goal - invoiced
                var days = missing.decimal / tjm.decimal
                var rounded = Decimal(); NSDecimalRound(&rounded, &days, 1, .up)
                out.append(Insight(id: "goal", title: "Il te manque \(NSDecimalNumber(decimal: rounded).stringValue.replacingOccurrences(of: ".", with: ",")) jours facturés pour ton objectif",
                                   detail: "Tu as facturé \(invoiced) ce mois-ci sur un objectif de \(goal) HT.",
                                   figures: [.init(label: "Reste à facturer", value: missing.description), .init(label: "TJM moyen", value: tjm.description)],
                                   period: "Mois en cours", assumptions: ["TJM moyen calculé sur tes lignes facturées en jours sur 12 mois (sinon ton TJM par défaut)."],
                                   reliability: .high, impact: missing, urgency: 1, target: .missions, actionLabel: "Voir les missions"))
            }
        }

        // 5. Travail réalisé non facturé
        let unbilled = finance.missionStats().filter { $0.uninvoicedWork.isPositive }
        if !unbilled.isEmpty {
            let total = unbilled.sum(\.uninvoicedWork)
            out.append(Insight(id: "unbilled", title: "\(total) de travail réalisé n'est pas encore facturé",
                               detail: "Jours travaillés saisis sur tes missions, moins ce qui a déjà été facturé.",
                               figures: unbilled.prefix(4).map { .init(label: $0.mission.title, value: $0.uninvoicedWork.description) },
                               period: "Missions en cours", assumptions: ["Jours travaillés × TJM de la mission."], reliability: .high,
                               impact: total, urgency: 2, target: .missions, actionLabel: "Facturer"))
        }

        // 6. Dépenses en hausse
        let prevMonth = month.previous(calendar: cal)
        let now = finance.expensesPaid(in: month).0, before = finance.expensesPaid(in: prevMonth).0
        if let d = PeriodComparison.delta(now, before), d > Decimal(string: "0.15")!, (now - before) > Money(euros: 50) {
            out.append(Insight(id: "expenses-up", title: "Tes dépenses ont progressé de \(MoneyFormat.percent(d, digits: 0))",
                               detail: "\(now) payés ce mois-ci contre \(before) le mois dernier.",
                               figures: [.init(label: "Ce mois", value: now.description), .init(label: "Mois dernier", value: before.description)],
                               period: "Mois en cours vs mois précédent", assumptions: ["Dépenses réellement payées uniquement ; le mois en cours n'est pas terminé."],
                               reliability: .medium, impact: now - before, urgency: 1, target: .expenses, actionLabel: "Voir les dépenses"))
        }

        // 7. Concentration client
        let year = Period(start: cal.date(byAdding: .month, value: -12, to: today)!, end: today)
        if let top = finance.clientStats(in: year).first, top.share > Decimal(string: "0.4")!, finance.ledger.clients.count >= 1, top.collected > Money(euros: 1000) {
            out.append(Insight(id: "concentration", title: "\(top.name) représente \(MoneyFormat.percent(top.share, digits: 0)) de tes encaissements",
                               detail: "Une forte dépendance à un client fragilise ta trésorerie s'il réduit ou retarde ses commandes.",
                               figures: [.init(label: "Encaissé de ce client", value: top.collected.description)],
                               period: "12 derniers mois", assumptions: ["Part des paiements reçus, pas du facturé."], reliability: .high,
                               impact: top.collected.applying(rate: Decimal(string: "0.1")!), urgency: 0, target: .clients, actionLabel: "Voir les clients"))
        }

        // 8. Dépenses récurrentes anciennes
        let old = finance.ledger.expenses.filter { $0.recurrence != .none && $0.status == .planned && cal.dateComponents([.month], from: $0.createdAt, to: today).month! >= 6 }
        for e in old.prefix(3) {
            let annual = e.recurrence == .monthly ? e.amount.times(12) : e.amount
            out.append(Insight(id: "recurring-\(e.id)", title: "« \(e.supplier.ifEmpty(e.label)) » est prévue depuis plusieurs mois",
                               detail: "Vérifie que cette dépense récurrente est toujours utile : elle représente \(annual) par an.",
                               figures: [.init(label: "Montant", value: "\(e.amount) · \(e.recurrence.label.lowercased())")],
                               period: "Depuis le \(fmtDate(e.createdAt))", assumptions: ["Montant annualisé."], reliability: .high,
                               impact: annual, urgency: 0, target: .expenses, actionLabel: "Voir la dépense"))
        }

        // 9. Seuils réglementaires
        for (i, msg) in finance.tax.thresholdAlerts(year: cal.component(.year, from: today), today: today).enumerated() {
            out.append(Insight(id: "threshold-\(i)", title: "Seuil réglementaire à surveiller", detail: msg, figures: [],
                               period: "Année civile en cours", assumptions: ["CA encaissé HT ; seuils du catalogue de règles."], reliability: .medium,
                               impact: Money(euros: 1000), urgency: 2, target: .settings, actionLabel: "Voir les règles"))
        }

        // 10. Obligations à vérifier
        let unknown = finance.allObligations().filter { $0.status == .toVerify && $0.period.start <= today }
        if !unknown.isEmpty {
            out.append(Insight(id: "toverify", title: "\(unknown.count) obligation\(unknown.count > 1 ? "s" : "") à vérifier",
                               detail: "Certaines estimations manquent d'une donnée (taux de prélèvement, montant de CFE, taux non couvert). Elles ne sont pas comptées dans tes réserves.",
                               figures: unknown.prefix(4).map { .init(label: $0.kind.shortLabel, value: $0.explanation) },
                               period: "Année en cours", assumptions: [], reliability: .low, impact: Money(euros: 500), urgency: 2,
                               target: .obligations, actionLabel: "Compléter"))
        }

        return out.sorted { ($0.urgency, $0.impact) > ($1.urgency, $1.impact) }
    }
}
