import Foundation

/// L'ensemble des données de l'utilisateur. Une seule source de vérité, versionnée.
public struct Ledger: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int = Ledger.currentSchemaVersion
    public var profile = BusinessProfile()
    public var clients: [Client] = []
    public var missions: [Mission] = []
    public var invoices: [Invoice] = []
    public var quotes: [Quote] = []
    public var expenses: [Expense] = []
    public var transactions: [BankTransaction] = []
    public var obligationRecords: [ObligationRecord] = []
    public var rules: TaxRuleSet = .defaultCatalogue
    /// Dernier numéro attribué par préfixe (ex. "F-2026" → 41). Ne décroît jamais.
    public var counters: [String: Int] = [:]
    public var auditLog: [HistoryEntry] = []

    public init() {}

    public func client(_ id: UUID?) -> Client? { id.flatMap { i in clients.first { $0.id == i } } }
    public func mission(_ id: UUID?) -> Mission? { id.flatMap { i in missions.first { $0.id == i } } }
    public func invoice(_ id: UUID?) -> Invoice? { id.flatMap { i in invoices.first { $0.id == i } } }
}

public enum LedgerError: LocalizedError, Equatable {
    case invoiceNotDraft, invoiceNotIssued, emptyInvoice, missingClient, missingIssuerInfo([String])
    case paymentExceedsBalance(balance: Money), nonPositiveAmount, quoteNotAccepted, alreadyInvoiced
    case duplicate, notFound, lineWithoutLabel

    public var errorDescription: String? {
        switch self {
        case .invoiceNotDraft: "Cette facture est déjà émise : elle ne peut plus être modifiée. Crée un avoir pour la corriger."
        case .invoiceNotIssued: "Cette action n'est possible que sur une facture émise."
        case .emptyInvoice: "Ajoute au moins une ligne avec un montant avant d'émettre."
        case .missingClient: "Choisis un client avant d'émettre."
        case .missingIssuerInfo(let f): "Complète tes informations d'émetteur : \(f.joined(separator: ", "))."
        case .paymentExceedsBalance(let b): "Le paiement dépasse le solde restant (\(b))."
        case .nonPositiveAmount: "Le montant doit être supérieur à zéro."
        case .quoteNotAccepted: "Seul un devis accepté peut être converti en facture."
        case .alreadyInvoiced: "Ce devis a déjà été converti en facture."
        case .duplicate: "Cette opération existe déjà."
        case .notFound: "Élément introuvable."
        case .lineWithoutLabel: "Chaque ligne doit avoir une désignation (description de la prestation)."
        }
    }
}

// MARK: - Opérations métier (pures, testables)

extension Ledger {
    mutating func nextNumber(prefix: String, year: Int) -> String {
        let key = "\(prefix)-\(year)"
        let n = (counters[key] ?? 0) + 1
        counters[key] = n
        return String(format: "%@-%04d", key, n)
    }

    mutating func log(_ action: String, at date: Date) {
        auditLog.append(HistoryEntry(date: date, action: action))
    }

    public func issueBlockers(_ invoice: Invoice) -> LedgerError? {
        if invoice.lifecycle != .draft { return .invoiceNotDraft }
        if invoice.clientId == nil || client(invoice.clientId) == nil { return .missingClient }
        if invoice.lines.isEmpty || !invoice.totals.ttc.isPositive { return .emptyInvoice }
        if invoice.lines.contains(where: { $0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { return .lineWithoutLabel }
        var missing: [String] = []
        if profile.displayName.trimmingCharacters(in: .whitespaces).isEmpty { missing.append("nom") }
        if profile.address.trimmingCharacters(in: .whitespaces).isEmpty { missing.append("adresse") }
        if profile.siret.filter(\.isNumber).count != 14 { missing.append("SIRET (14 chiffres)") }
        return missing.isEmpty ? nil : .missingIssuerInfo(missing)
    }

    /// Émet une facture : attribue le numéro suivant, fige client, émetteur et mentions.
    @discardableResult
    public mutating func issueInvoice(id: UUID, on date: Date, calendar: Calendar = .fr) throws -> Invoice {
        guard let i = invoices.firstIndex(where: { $0.id == id }) else { throw LedgerError.notFound }
        if let e = issueBlockers(invoices[i]) { throw e }
        let year = calendar.component(.year, from: date)
        var inv = invoices[i]
        inv.number = nextNumber(prefix: inv.kind == .creditNote ? "A" : "F", year: year)
        inv.lifecycle = .issued
        inv.issueDate = date
        if inv.dueDate < date { inv.dueDate = date }
        inv.vatApplicable = profile.vatRegime == .redevable
        inv.clientSnapshot = client(inv.clientId).map(PartySnapshot.of(client:))
        inv.issuerSnapshot = PartySnapshot.of(profile: profile)
        inv.legalMentions = profile.legalMentions
        if inv.paymentTerms.isEmpty {
            inv.paymentTerms = "Paiement à \(profile.paymentTermDays) jours. \(profile.latePenaltyText)"
        }
        inv.history.append(HistoryEntry(date: date, action: "Émise sous le numéro \(inv.number!)"))
        invoices[i] = inv
        log("Facture \(inv.number!) émise", at: date)
        return inv
    }

    public mutating func recordPayment(invoiceId: UUID, payment: Payment) throws {
        guard let i = invoices.firstIndex(where: { $0.id == invoiceId }) else { throw LedgerError.notFound }
        guard invoices[i].lifecycle == .issued, invoices[i].kind == .invoice else { throw LedgerError.invoiceNotIssued }
        guard payment.amount.isPositive else { throw LedgerError.nonPositiveAmount }
        let balance = invoices[i].balance
        guard payment.amount <= balance else { throw LedgerError.paymentExceedsBalance(balance: balance) }
        if let t = payment.transactionId, invoices.contains(where: { $0.payments.contains { $0.transactionId == t } }) {
            throw LedgerError.duplicate
        }
        invoices[i].payments.append(payment)
        invoices[i].history.append(HistoryEntry(date: payment.date, action: "Paiement de \(payment.amount) reçu (\(payment.method.label))"))
        if let t = payment.transactionId, let ti = transactions.firstIndex(where: { $0.id == t }) {
            transactions[ti].linkedInvoiceId = invoiceId
        }
        log("Paiement \(payment.amount) sur \(invoices[i].number ?? "?")", at: payment.date)
    }

    public mutating func removePayment(invoiceId: UUID, paymentId: UUID, on date: Date) {
        guard let i = invoices.firstIndex(where: { $0.id == invoiceId }),
              let p = invoices[i].payments.first(where: { $0.id == paymentId }) else { return }
        invoices[i].payments.removeAll { $0.id == paymentId }
        invoices[i].history.append(HistoryEntry(date: date, action: "Paiement de \(p.amount) du \(p.date.formatted(date: .numeric, time: .omitted)) supprimé"))
        if let t = p.transactionId, let ti = transactions.firstIndex(where: { $0.id == t }) { transactions[ti].linkedInvoiceId = nil }
    }

    /// Annule une facture émise en créant un avoir du montant restant dû, numéroté dans sa propre séquence.
    /// Le numéro de la facture d'origine n'est jamais réutilisé.
    @discardableResult
    public mutating func cancelInvoice(id: UUID, on date: Date, reason: String) throws -> Invoice {
        guard let i = invoices.firstIndex(where: { $0.id == id }) else { throw LedgerError.notFound }
        let original = invoices[i]
        guard original.lifecycle == .issued, original.kind == .invoice else { throw LedgerError.invoiceNotIssued }
        var credit = Invoice(clientId: original.clientId, issueDate: date, dueDate: date)
        credit.kind = .creditNote
        credit.correctsInvoiceId = original.id
        credit.missionId = original.missionId
        // L'avoir reprend les lignes (montant total) ; les paiements déjà reçus restent acquis et visibles.
        credit.lines = original.lines
        credit.discount = original.discount
        credit.notes = "Avoir sur la facture \(original.number ?? "") — \(reason)"
        invoices.append(credit)
        let issued = try issueInvoice(id: credit.id, on: date)
        invoices[i].lifecycle = .cancelled
        invoices[i].history.append(HistoryEntry(date: date, action: "Annulée par l'avoir \(issued.number ?? "") — \(reason)"))
        return issued
    }

    /// Convertit un devis accepté en facture brouillon (l'émission reste une action explicite).
    @discardableResult
    public mutating func convertQuote(id: UUID, on date: Date, calendar: Calendar = .fr) throws -> Invoice {
        guard let q = quotes.firstIndex(where: { $0.id == id }) else { throw LedgerError.notFound }
        guard quotes[q].invoiceId == nil else { throw LedgerError.alreadyInvoiced }
        guard quotes[q].status == .accepted else { throw LedgerError.quoteNotAccepted }
        var inv = Invoice(clientId: quotes[q].clientId, issueDate: date,
                          dueDate: calendar.date(byAdding: .day, value: profile.paymentTermDays, to: date)!)
        inv.lines = quotes[q].lines.map { var l = $0; l.id = UUID(); return l }
        inv.discount = quotes[q].discount
        inv.missionId = quotes[q].missionId
        inv.quoteId = quotes[q].id
        inv.notes = quotes[q].number.map { "Selon devis \($0)" } ?? ""
        inv.history.append(HistoryEntry(date: date, action: "Créée depuis le devis \(quotes[q].number ?? "")"))
        invoices.append(inv)
        quotes[q].invoiceId = inv.id
        quotes[q].status = .invoiced
        quotes[q].history.append(HistoryEntry(date: date, action: "Converti en facture"))
        return inv
    }

    public mutating func finalizeQuote(id: UUID, on date: Date, calendar: Calendar = .fr) throws {
        guard let q = quotes.firstIndex(where: { $0.id == id }) else { throw LedgerError.notFound }
        guard quotes[q].clientId != nil else { throw LedgerError.missingClient }
        guard !quotes[q].lines.isEmpty else { throw LedgerError.emptyInvoice }
        guard !quotes[q].lines.contains(where: { $0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw LedgerError.lineWithoutLabel }
        if quotes[q].number == nil {
            quotes[q].number = nextNumber(prefix: "D", year: calendar.component(.year, from: date))
        }
        quotes[q].status = .sent
        quotes[q].issueDate = date
        quotes[q].vatApplicable = profile.vatRegime == .redevable
        quotes[q].clientSnapshot = client(quotes[q].clientId).map(PartySnapshot.of(client:))
        quotes[q].issuerSnapshot = PartySnapshot.of(profile: profile)
        quotes[q].legalMentions = profile.legalMentions
        quotes[q].history.append(HistoryEntry(date: date, action: "Finalisé sous le numéro \(quotes[q].number!)"))
    }

    /// Supprime un brouillon. Les factures émises ne se suppriment jamais (obligation de conservation).
    public mutating func deleteDraft(id: UUID) throws {
        guard let i = invoices.firstIndex(where: { $0.id == id }) else { throw LedgerError.notFound }
        guard invoices[i].lifecycle == .draft else { throw LedgerError.invoiceNotDraft }
        invoices.remove(at: i)
    }

    /// Paye une dépense prévue (ou une occurrence d'une dépense récurrente).
    public mutating func markExpensePaid(id: UUID, on date: Date) {
        guard let i = expenses.firstIndex(where: { $0.id == id }) else { return }
        if expenses[i].recurrence == .none {
            expenses[i].status = .paid
            expenses[i].date = date
        } else {
            // La règle récurrente reste ; on crée l'occurrence payée.
            var paid = expenses[i]
            paid.id = UUID(); paid.recurrence = .none; paid.status = .paid; paid.date = date; paid.recurrenceEnd = nil
            paid.createdAt = date
            expenses.append(paid)
            let step: DateComponents = expenses[i].recurrence == .monthly ? DateComponents(month: 1) : DateComponents(year: 1)
            expenses[i].date = Calendar.fr.date(byAdding: step, to: expenses[i].date)!
        }
    }

    public mutating func updateObligationRecord(_ record: ObligationRecord) {
        if let i = obligationRecords.firstIndex(where: { $0.key == record.key }) { obligationRecords[i] = record }
        else { obligationRecords.append(record) }
    }
}
