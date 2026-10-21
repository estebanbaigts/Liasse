import Foundation

/// Une ligne source qui explique un montant (traçabilité jusqu'à la transaction).
public struct TraceItem: Identifiable, Hashable, Sendable {
    public enum Source: Hashable, Sendable { case invoice(UUID), payment(invoice: UUID, payment: UUID), expense(UUID), obligation(String), opening }
    public var id = UUID()
    public var date: Date
    public var label: String
    public var amount: Money
    public var source: Source
    public init(date: Date, label: String, amount: Money, source: Source) { self.date = date; self.label = label; self.amount = amount; self.source = source }
}

public struct Dashboard: Sendable {
    public var period: Period
    public var invoicedHT: Money
    public var invoicedTrace: [TraceItem]
    public var collected: Money
    public var collectedHT: Money
    public var collectedTrace: [TraceItem]
    public var expensesPaid: Money
    public var expensesPaidTrace: [TraceItem]
    public var expensesPlanned: Money
    public var expensesPlannedTrace: [TraceItem]
    public var reserves: ReserveSplit
    public var cashResult: Money { collected - expensesPaid }
    /// Disponible sur la période = encaissé − dépenses payées − réserves estimées.
    public var available: Money { collected - expensesPaid - reserves.total }
    // Toujours « à date », indépendants de la période choisie
    public var receivables: Money
    public var receivableInvoices: [Invoice]
    public var overdue: Money
    public var overdueInvoices: [Invoice]
    public var previous: PeriodComparison
    public var upcoming: [Deadline]
    public var cash: CashPosition
}

public struct PeriodComparison: Sendable {
    public var collected: Money
    public var expensesPaid: Money
    public var available: Money
    public static func delta(_ now: Money, _ before: Money) -> Decimal? {
        guard !before.isZero else { return nil }
        return (now.decimal - before.decimal) / abs(before.decimal)
    }
}

public struct Deadline: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable { case obligation(ObligationKind, ObligationStatus), expense, receivable }
    public var id: String
    public var date: Date
    public var title: String
    public var detail: String
    public var amount: Money
    public var kind: Kind
    public var isEstimate: Bool
}

public struct CashPosition: Sendable {
    /// Solde bancaire reconstitué : solde d'ouverture + encaissements − dépenses payées − obligations payées.
    public var balance: Money
    public var balanceTrace: [TraceItem]
    /// Obligations nées (périodes commencées) non encore payées.
    public var reservesOutstanding: Money
    public var reserveObligations: [Obligation]
    public var free: Money { balance - reservesOutstanding }
}

public struct FinanceEngine: Sendable {
    public let ledger: Ledger
    public let today: Date
    public let calendar: Calendar
    public let tax: TaxEngine

    public init(ledger: Ledger, today: Date, calendar: Calendar = .fr) {
        self.ledger = ledger; self.today = today; self.calendar = calendar
        self.tax = TaxEngine(ledger: ledger, calendar: calendar)
    }

    // MARK: Facturé / encaissé

    /// Facturé HT : factures émises (y compris annulées ensuite) moins avoirs, à leur date d'émission. Jamais les brouillons.
    public func invoiced(in p: Period) -> (Money, [TraceItem]) {
        let items = ledger.invoices.filter { $0.lifecycle != .draft && p.contains($0.issueDate, calendar: calendar) }.map { inv in
            let amount = inv.kind == .creditNote ? -inv.totals.netHT : inv.totals.netHT
            return TraceItem(date: inv.issueDate, label: "\(inv.kind == .creditNote ? "Avoir" : "Facture") \(inv.number ?? "") · \(clientName(inv))", amount: amount, source: .invoice(inv.id))
        }
        return (items.sum(\.amount), items.sorted { $0.date < $1.date })
    }

    public func collected(in p: Period) -> (Money, [TraceItem]) {
        let items = tax.collectedPayments(in: p).map { pair in
            TraceItem(date: pair.payment.date, label: "\(clientName(pair.invoice)) · \(pair.invoice.number ?? "")", amount: pair.payment.amount,
                      source: .payment(invoice: pair.invoice.id, payment: pair.payment.id))
        }
        return (items.sum(\.amount), items.sorted { $0.date < $1.date })
    }

    public func clientName(_ inv: Invoice) -> String { inv.clientSnapshot?.name ?? ledger.client(inv.clientId)?.name ?? "Client" }

    // MARK: Dépenses

    public func expensesPaid(in p: Period) -> (Money, [TraceItem]) {
        let items = ledger.expenses.filter { $0.status == .paid && p.contains($0.date, calendar: calendar) }.map {
            TraceItem(date: $0.date, label: [$0.supplier, $0.label].filter { !$0.isEmpty }.joined(separator: " · ").ifEmpty($0.category.label), amount: $0.amount, source: .expense($0.id))
        }
        return (items.sum(\.amount), items.sorted { $0.date < $1.date })
    }

    /// Occurrences des dépenses prévues (récurrences comprises) dans une période.
    public func plannedOccurrences(in p: Period) -> [(expense: Expense, date: Date)] {
        var out: [(Expense, Date)] = []
        for e in ledger.expenses where e.status == .planned {
            var d = e.date
            var guardCount = 0
            while d <= p.end && guardCount < 500 {
                if let end = e.recurrenceEnd, d > end { break }
                if p.contains(d, calendar: calendar) { out.append((e, d)) }
                guard e.recurrence != .none else { break }
                d = calendar.date(byAdding: e.recurrence == .monthly ? DateComponents(month: 1) : DateComponents(year: 1), to: d)!
                guardCount += 1
            }
        }
        return out.sorted { $0.1 < $1.1 }
    }

    public func expensesPlanned(in p: Period) -> (Money, [TraceItem]) {
        let items = plannedOccurrences(in: p).map { o in
            TraceItem(date: o.date, label: [o.expense.supplier, o.expense.label].filter { !$0.isEmpty }.joined(separator: " · ").ifEmpty(o.expense.category.label), amount: o.expense.amount, source: .expense(o.expense.id))
        }
        return (items.sum(\.amount), items)
    }

    // MARK: Créances

    public var openInvoices: [Invoice] {
        ledger.invoices.filter { $0.kind == .invoice && $0.lifecycle == .issued && $0.balance.isPositive }
            .sorted { $0.dueDate < $1.dueDate }
    }

    public var overdueInvoices: [Invoice] { openInvoices.filter { $0.status(on: today, calendar: calendar) == .overdue } }

    // MARK: Obligations et trésorerie

    public func allObligations() -> [Obligation] {
        let y = calendar.component(.year, from: today)
        let startY = calendar.component(.year, from: ledger.profile.activityStart)
        return (max(startY, y - 1)...y + 1).flatMap { tax.obligations(year: $0, today: today) }
    }

    public func cashPosition() -> CashPosition {
        let p = ledger.profile
        let since = Period(start: p.openingBalanceDate, end: calendar.date(byAdding: .year, value: 50, to: today)!)
        var trace = [TraceItem(date: p.openingBalanceDate, label: "Solde de départ saisi", amount: p.openingBalance, source: .opening)]
        // Le solde de départ s'entend au début de la journée indiquée : tout mouvement de ce jour-là ou après est ajouté.
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: today))!
        let afterOpening: (Date) -> Bool = { $0 >= calendar.startOfDay(for: p.openingBalanceDate) && $0 < endOfToday }
        for pair in tax.collectedPayments(in: since) where afterOpening(pair.payment.date) {
            trace.append(TraceItem(date: pair.payment.date, label: "Encaissement · \(clientName(pair.invoice))", amount: pair.payment.amount, source: .payment(invoice: pair.invoice.id, payment: pair.payment.id)))
        }
        for e in ledger.expenses where e.status == .paid && afterOpening(e.date) {
            trace.append(TraceItem(date: e.date, label: "Dépense · \(e.supplier.ifEmpty(e.category.label))", amount: -e.amount, source: .expense(e.id)))
        }
        let obligations = allObligations()
        for o in obligations {
            if let paid = o.record?.paidAmount, let d = o.record?.paidDate, afterOpening(d) {
                trace.append(TraceItem(date: d, label: "Paiement · \(o.kind.shortLabel)", amount: -paid, source: .obligation(o.key)))
            }
        }
        let started = obligations.filter { $0.period.start <= today && $0.status != .paid && $0.remaining.isPositive }
        return CashPosition(balance: trace.sum(\.amount), balanceTrace: trace.sorted { $0.date < $1.date },
                            reservesOutstanding: started.sum(\.remaining), reserveObligations: started)
    }

    public func upcoming(days: Int = 90) -> [Deadline] {
        let horizon = calendar.date(byAdding: .day, value: days, to: today)!
        let window = Period(start: today, end: horizon)
        var out: [Deadline] = []
        for o in allObligations() where o.status != .paid && o.dueDate <= horizon && o.dueDate >= calendar.date(byAdding: .day, value: -60, to: today)! {
            let amount = o.remaining
            guard amount.isPositive || o.status == .toVerify || o.status == .toDeclare else { continue }
            out.append(Deadline(id: o.key, date: o.dueDate, title: tax.label(o),
                                detail: o.status.label, amount: amount, kind: .obligation(o.kind, o.status), isEstimate: o.record?.declaredAmount == nil))
        }
        for occ in plannedOccurrences(in: window) {
            out.append(Deadline(id: "exp-\(occ.expense.id)-\(occ.date.timeIntervalSince1970)", date: occ.date, title: occ.expense.supplier.ifEmpty(occ.expense.label.ifEmpty(occ.expense.category.label)),
                                detail: "Dépense prévue", amount: occ.expense.amount, kind: .expense, isEstimate: false))
        }
        return out.sorted { $0.date < $1.date }
    }

    // MARK: Tableau de bord

    public func dashboard(period p: Period) -> Dashboard {
        let (inv, invT) = invoiced(in: p)
        let (col, colT) = collected(in: p)
        let (paid, paidT) = expensesPaid(in: p)
        let (planned, plannedT) = expensesPlanned(in: p)
        let split = tax.split(collectedHT: tax.collectedHT(in: p), vat: tax.vatCollected(in: p), on: p.start)
        let prevP = p.previous(calendar: calendar)
        let prevCol = collected(in: prevP).0, prevPaid = expensesPaid(in: prevP).0
        let prevSplit = tax.split(collectedHT: tax.collectedHT(in: prevP), vat: tax.vatCollected(in: prevP), on: prevP.start)
        let open = openInvoices, late = overdueInvoices
        return Dashboard(period: p, invoicedHT: inv, invoicedTrace: invT, collected: col, collectedHT: split.collectedHT, collectedTrace: colT,
                         expensesPaid: paid, expensesPaidTrace: paidT, expensesPlanned: planned, expensesPlannedTrace: plannedT,
                         reserves: split, receivables: open.sum(\.balance), receivableInvoices: open,
                         overdue: late.sum(\.balance), overdueInvoices: late,
                         previous: PeriodComparison(collected: prevCol, expensesPaid: prevPaid, available: prevCol - prevPaid - prevSplit.total),
                         upcoming: upcoming(), cash: cashPosition())
    }

    // MARK: Rentabilité

    public struct ClientStats: Identifiable, Sendable {
        public var id: UUID
        public var name: String
        public var invoicedHT: Money
        public var collected: Money
        public var outstanding: Money
        public var share: Decimal
    }

    public func clientStats(in p: Period) -> [ClientStats] {
        let total = collected(in: p).0
        return ledger.clients.map { c in
            let invs = ledger.invoices.filter { $0.clientId == c.id && $0.lifecycle != .draft }
            let invd = invs.filter { p.contains($0.issueDate, calendar: calendar) }.sum { $0.kind == .creditNote ? -$0.totals.netHT : $0.totals.netHT }
            let col = invs.filter { $0.kind == .invoice }.flatMap(\.payments).filter { p.contains($0.date, calendar: calendar) }.sum(\.amount)
            let out = invs.filter { $0.kind == .invoice && $0.lifecycle == .issued }.sum(\.balance)
            return ClientStats(id: c.id, name: c.name, invoicedHT: invd, collected: col, outstanding: out,
                               share: total.isZero ? 0 : col.decimal / total.decimal)
        }.sorted { $0.collected > $1.collected }
    }

    public struct MissionStats: Identifiable, Sendable {
        public var id: UUID
        public var mission: Mission
        public var invoicedHT: Money
        public var collected: Money
        public var expenses: Money
        /// Rentabilité économique (hors cotisations) : encaissé HT − frais − dépenses liées.
        public var margin: Money
        public var effectiveDailyRate: Money?
        public var uninvoicedWork: Money
    }

    public func missionStats() -> [MissionStats] {
        ledger.missions.map { m in
            let invs = ledger.invoices.filter { $0.missionId == m.id && $0.lifecycle != .draft }
            let invd = invs.sum { $0.kind == .creditNote ? -$0.totals.netHT : $0.totals.netHT }
            let col = invs.filter { $0.kind == .invoice }.flatMap { inv in inv.payments.map { tax.htPart(of: $0, in: inv) } }.sum { $0 }
            let exp = ledger.expenses.filter { $0.missionId == m.id && $0.status == .paid }.sum { $0.amount - $0.vatAmount }
            let margin = col - m.fees - exp
            let rate: Money? = m.workedDays > 0 ? Money(decimalEuros: (invd - m.fees - exp).decimal / m.workedDays) : nil
            let worked = m.dailyRate.times(m.workedDays)
            return MissionStats(id: m.id, mission: m, invoicedHT: invd, collected: col, expenses: exp, margin: margin,
                                effectiveDailyRate: rate, uninvoicedWork: (worked - invd).clamped(min: .zero))
        }.sorted { $0.margin > $1.margin }
    }

    /// Taux journalier moyen observé (lignes en jours des factures émises sur 12 mois), sinon le TJM par défaut.
    public func averageDailyRate() -> Money {
        let p = Period(start: calendar.date(byAdding: .month, value: -12, to: today)!, end: today)
        let lines = ledger.invoices.filter { $0.kind == .invoice && $0.lifecycle != .draft && p.contains($0.issueDate, calendar: calendar) }
            .flatMap(\.lines).filter { $0.unit == .day && $0.quantity > 0 }
        let days = lines.reduce(Decimal(0)) { $0 + $1.quantity }
        guard days > 0 else { return ledger.profile.defaultDailyRate }
        return Money(decimalEuros: lines.sum(\.totalHT).decimal / days)
    }

    /// Part du CA qui reste après cotisations, CFP et impôt estimés (hors dépenses).
    public func netRatio(on date: Date) -> Decimal {
        let s = tax.split(collectedHT: Money(euros: 10_000), vat: .zero, on: date)
        return (s.collectedHT - s.cotisations - s.cfp - s.incomeTax).decimal / s.collectedHT.decimal
    }

    /// CA à encaisser pour atteindre un revenu net mensuel donné, compte tenu des dépenses moyennes.
    public func revenueNeeded(netTarget: Money, monthlyExpenses: Money) -> (revenue: Money, days: Decimal, dailyRate: Money) {
        let ratio = netRatio(on: today)
        guard ratio > 0 else { return (.zero, 0, averageDailyRate()) }
        let revenue = Money(decimalEuros: (netTarget + monthlyExpenses).decimal / ratio)
        let tjm = averageDailyRate()
        let days = tjm.isPositive ? revenue.decimal / tjm.decimal : 0
        return (revenue, days, tjm)
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
