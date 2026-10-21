import Foundation

public enum Scenario: String, CaseIterable, Identifiable, Sendable, Codable {
    case optimistic, realistic, prudent
    public var id: String { rawValue }
    public var label: String { switch self { case .optimistic: "Optimiste"; case .realistic: "Réaliste"; case .prudent: "Prudent" } }
}

/// Hypothèses modifiables par l'utilisateur.
public struct ForecastAssumptions: Codable, Hashable, Sendable {
    /// Retard de paiement supposé (jours après l'échéance) en scénario réaliste. Nil = moyenne observée.
    public var realisticDelayDays: Int? = nil
    public var prudentExtraDelayDays: Int = 30
    /// Au-delà de ce retard, une facture n'est plus comptée en scénario réaliste.
    public var realisticOverdueCutoffDays: Int = 60
    /// Inclure le travail planifié non facturé des missions en cours (scénario optimiste seulement).
    public var includeUninvoicedMissions: Bool = true
    /// Seuil d'alerte de trésorerie.
    public var safetyThreshold: Money = .zero
    public init() {}
}

public struct ForecastEvent: Identifiable, Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable { case receivable, plannedWork, expense, obligation, reserveOnInflow }
    public var id = UUID()
    public var date: Date
    public var label: String
    public var amount: Money
    public var kind: Kind
    public var note: String
    public init(date: Date, label: String, amount: Money, kind: Kind, note: String) {
        self.date = date; self.label = label; self.amount = amount; self.kind = kind; self.note = note
    }
}

public struct ForecastPoint: Hashable, Sendable { public var date: Date; public var balance: Money }

public struct ForecastResult: Sendable {
    public var scenario: Scenario
    public var start: Money
    public var events: [ForecastEvent]
    public var points: [ForecastPoint]
    public var low: ForecastPoint
    public var firstBelowThreshold: Date?
    public var assumptions: [String]
    public func balance(at day: Int) -> Money { points[min(max(day, 0), points.count - 1)].balance }
}

public struct ForecastEngine: Sendable {
    public let finance: FinanceEngine
    public var assumptions: ForecastAssumptions
    public init(finance: FinanceEngine, assumptions: ForecastAssumptions = .init()) { self.finance = finance; self.assumptions = assumptions }

    var cal: Calendar { finance.calendar }
    var today: Date { cal.startOfDay(for: finance.today) }

    /// Retard moyen observé (jours) sur les factures soldées, 10 par défaut faute d'historique.
    public func observedDelay() -> Int {
        let paid = finance.ledger.invoices.filter { $0.kind == .invoice && $0.lifecycle == .issued && $0.balance.isZero && !$0.payments.isEmpty }
        let delays = paid.compactMap { inv -> Int? in
            guard let last = inv.payments.map(\.date).max() else { return nil }
            return max(0, cal.dateComponents([.day], from: cal.startOfDay(for: inv.dueDate), to: cal.startOfDay(for: last)).day ?? 0)
        }
        guard !delays.isEmpty else { return 10 }
        return delays.reduce(0, +) / delays.count
    }

    public func run(_ scenario: Scenario, days: Int = 90) -> ForecastResult {
        let end = cal.date(byAdding: .day, value: days, to: today)!
        let window = Period(start: cal.date(byAdding: .day, value: 1, to: today)!, end: end)
        let cash = finance.cashPosition()
        var events: [ForecastEvent] = []
        var notes: [String] = ["Départ : solde reconstitué au \(today.formatted(date: .abbreviated, time: .omitted)) (\(cash.balance)). Les prévisions ne sont jamais ajoutées à l'encaissé."]
        let delay = assumptions.realisticDelayDays ?? observedDelay()
        let tax = finance.tax

        func inflowDate(_ inv: Invoice) -> Date? {
            let late = inv.daysLate(on: today, calendar: cal)
            switch scenario {
            case .optimistic:
                return max(cal.startOfDay(for: inv.dueDate), cal.date(byAdding: .day, value: 1, to: today)!)
            case .realistic:
                if late > assumptions.realisticOverdueCutoffDays { return nil }
                let d = cal.date(byAdding: .day, value: delay, to: cal.startOfDay(for: inv.dueDate))!
                return max(d, cal.date(byAdding: .day, value: 7, to: today)!)
            case .prudent:
                if late > 0 { return nil }
                return cal.date(byAdding: .day, value: delay + assumptions.prudentExtraDelayDays, to: cal.startOfDay(for: inv.dueDate))!
            }
        }

        // Encaissements attendus + la réserve qu'ils créeront, payée à l'échéance URSSAF de leur période.
        for inv in finance.openInvoices {
            guard let d = inflowDate(inv), d <= end else { continue }
            let pay = Payment(date: d, amount: inv.balance)
            events.append(ForecastEvent(date: d, label: "\(finance.clientName(inv)) · \(inv.number ?? "")", amount: inv.balance, kind: .receivable,
                                        note: "Solde restant de la facture, échéance \(inv.dueDate.formatted(date: .abbreviated, time: .omitted))"))
            let split = tax.split(payment: pay, invoice: inv)
            let period = finance.ledger.profile.urssafPeriodicity == .monthly ? Period.month(of: d, calendar: cal) : Period.quarter(of: d, calendar: cal)
            let due = tax.urssafDueDate(for: period)
            let social = split.cotisations + split.cfp + (finance.ledger.profile.versementLiberatoire ? split.incomeTax : .zero)
            if social.isPositive && due <= end {
                events.append(ForecastEvent(date: due, label: "Cotisations sur \(inv.number ?? "encaissement")", amount: -social, kind: .reserveOnInflow,
                                            note: "Cotisations estimées sur cet encaissement futur"))
            }
        }
        switch scenario {
        case .optimistic: notes.append("Optimiste : chaque facture est payée à son échéance (les retards dès demain).")
        case .realistic: notes.append("Réaliste : paiement \(delay) j après l'échéance\(assumptions.realisticDelayDays == nil ? " (retard moyen observé)" : ""), factures en retard de plus de \(assumptions.realisticOverdueCutoffDays) j exclues.")
        case .prudent: notes.append("Prudent : factures en retard exclues, les autres payées \(delay + assumptions.prudentExtraDelayDays) j après l'échéance.")
        }

        // Travail planifié non facturé (optimiste)
        if scenario == .optimistic && assumptions.includeUninvoicedMissions {
            for m in finance.ledger.missions where m.status != .done {
                let invoiced = finance.ledger.invoices.filter { $0.missionId == m.id && $0.lifecycle != .draft }.sum(\.totals.netHT)
                let remaining = (m.plannedAmount - invoiced).clamped(min: .zero)
                guard remaining.isPositive else { continue }
                let base = m.endDate.map { max($0, today) } ?? cal.date(byAdding: .day, value: 30, to: today)!
                let d = cal.date(byAdding: .day, value: finance.ledger.profile.paymentTermDays, to: base)!
                if d <= end {
                    events.append(ForecastEvent(date: d, label: "Mission « \(m.title) » (non facturée)", amount: remaining, kind: .plannedWork,
                                                note: "Jours prévus non encore facturés"))
                }
            }
            notes.append("Optimiste : le travail prévu non facturé des missions en cours est inclus.")
        }

        // Dépenses prévues
        for occ in finance.plannedOccurrences(in: window) {
            events.append(ForecastEvent(date: occ.date, label: occ.expense.supplier.ifEmpty(occ.expense.label.ifEmpty(occ.expense.category.label)),
                                        amount: -occ.expense.amount, kind: .expense, note: occ.expense.recurrence == .none ? "Dépense prévue" : "Dépense récurrente (\(occ.expense.recurrence.label.lowercased()))"))
        }
        // Obligations déjà nées, non payées
        for o in finance.allObligations() where o.status != .paid && o.remaining.isPositive && o.period.start <= today {
            let d = max(o.dueDate, cal.date(byAdding: .day, value: 1, to: today)!)
            guard d <= end else { continue }
            events.append(ForecastEvent(date: d, label: tax.label(o),
                                        amount: -o.remaining, kind: .obligation, note: o.record?.declaredAmount != nil ? "Montant déclaré" : "Montant estimé"))
        }
        events.sort { $0.date < $1.date }

        var points: [ForecastPoint] = []
        var bal = cash.balance
        var idx = 0
        var firstBelow: Date?
        for day in 0...days {
            let d = cal.date(byAdding: .day, value: day, to: today)!
            while idx < events.count && cal.startOfDay(for: events[idx].date) <= d { bal += events[idx].amount; idx += 1 }
            points.append(ForecastPoint(date: d, balance: bal))
            if firstBelow == nil && bal < assumptions.safetyThreshold { firstBelow = d }
        }
        let low = points.min { $0.balance < $1.balance }!
        return ForecastResult(scenario: scenario, start: cash.balance, events: events, points: points, low: low,
                              firstBelowThreshold: firstBelow, assumptions: notes)
    }
}
