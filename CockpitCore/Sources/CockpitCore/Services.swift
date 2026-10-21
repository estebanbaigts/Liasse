import Foundation
import CryptoKit

// MARK: - Import CSV bancaire

public struct CSVImportResult: Sendable {
    public var transactions: [BankTransaction]
    public var duplicates: Int
    public var skippedLines: [Int]
    public var mapping: CSVMapping
}

public struct CSVMapping: Hashable, Sendable {
    public var delimiter: Character
    public var dateColumn: Int
    public var labelColumn: Int
    /// Soit une colonne montant signée, soit débit/crédit séparés.
    public var amountColumn: Int?
    public var debitColumn: Int?
    public var creditColumn: Int?
    public var hasHeader: Bool
}

public enum CSVImporter {
    public static func split(_ line: String, delimiter: Character) -> [String] {
        var out: [String] = [], cur = "", quoted = false
        var it = Array(line), i = 0
        while i < it.count {
            let c = it[i]
            if c == "\"" {
                if quoted && i + 1 < it.count && it[i + 1] == "\"" { cur.append("\""); i += 1 } else { quoted.toggle() }
            } else if c == delimiter && !quoted { out.append(cur.trimmingCharacters(in: .whitespaces)); cur = "" }
            else { cur.append(c) }
            i += 1
        }
        out.append(cur.trimmingCharacters(in: .whitespaces))
        it.removeAll()
        return out
    }

    static let dateFormats = ["dd/MM/yyyy", "yyyy-MM-dd", "dd-MM-yyyy", "dd.MM.yyyy", "dd/MM/yy", "yyyy/MM/dd"]

    public static func parseDate(_ s: String, calendar: Calendar = .fr) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR"); f.timeZone = calendar.timeZone; f.calendar = calendar
        for fmt in dateFormats {
            f.dateFormat = fmt
            if let d = f.date(from: s.trimmingCharacters(in: .whitespaces)) {
                return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: d)
            }
        }
        return nil
    }

    /// Devine les colonnes à partir de l'en-tête (formats courants des banques françaises).
    public static func detectMapping(_ text: String) -> CSVMapping? {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let first = lines.first else { return nil }
        let candidates: [Character] = [";", ",", "\t"]
        let delimiter = candidates.max { a, b in first.filter { $0 == a }.count < first.filter { $0 == b }.count }!
        let header = split(first, delimiter: delimiter).map { $0.lowercased().folding(options: .diacriticInsensitive, locale: nil) }
        func col(_ keys: [String]) -> Int? { header.firstIndex { h in keys.contains { h.contains($0) } } }
        if let d = col(["date"]) {
            let label = col(["libelle", "label", "description", "intitule", "operation", "detail"]) ?? (d == 0 ? 1 : 0)
            let debit = col(["debit"]), credit = col(["credit"])
            let amount = col(["montant", "amount", "somme", "valeur"])
            if amount == nil && (debit == nil || credit == nil) { return nil }
            return CSVMapping(delimiter: delimiter, dateColumn: d, labelColumn: label, amountColumn: amount,
                              debitColumn: amount == nil ? debit : nil, creditColumn: amount == nil ? credit : nil, hasHeader: true)
        }
        // Sans en-tête : date ; libellé ; montant
        let cells = split(first, delimiter: delimiter)
        if cells.count >= 3, parseDate(cells[0]) != nil, MoneyFormat.parse(cells[cells.count - 1]) != nil {
            return CSVMapping(delimiter: delimiter, dateColumn: 0, labelColumn: 1, amountColumn: cells.count - 1, debitColumn: nil, creditColumn: nil, hasHeader: false)
        }
        return nil
    }

    public static func fingerprint(date: Date, amount: Money, label: String, occurrence: Int, calendar: Calendar = .fr) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let norm = label.lowercased().folding(options: .diacriticInsensitive, locale: nil).filter { $0.isLetter || $0.isNumber }
        let raw = "\(c.year!)-\(c.month!)-\(c.day!)|\(amount.cents)|\(norm)|\(occurrence)"
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Analyse un relevé. Les doublons (même empreinte qu'une opération déjà importée) sont écartés.
    /// Deux opérations identiques le même jour dans le même fichier restent distinctes (rang d'occurrence).
    public static func parse(_ text: String, mapping: CSVMapping? = nil, existing: Set<String>, calendar: Calendar = .fr) -> CSVImportResult? {
        guard let m = mapping ?? detectMapping(text) else { return nil }
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        var seen: [String: Int] = [:]
        var txs: [BankTransaction] = [], dup = 0, skipped: [Int] = []
        var known = existing
        for (n, line) in lines.enumerated() {
            if n == 0 && m.hasHeader { continue }
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let c = split(line, delimiter: m.delimiter)
            func cell(_ i: Int?) -> String? { i.flatMap { $0 < c.count ? c[$0] : nil } }
            guard let ds = cell(m.dateColumn), let date = parseDate(ds, calendar: calendar) else { skipped.append(n + 1); continue }
            var amount: Money?
            if let a = cell(m.amountColumn) { amount = MoneyFormat.parse(a) }
            else {
                let debit = cell(m.debitColumn).flatMap { $0.isEmpty ? nil : MoneyFormat.parse($0) }
                let credit = cell(m.creditColumn).flatMap { $0.isEmpty ? nil : MoneyFormat.parse($0) }
                if let d = debit { amount = d.isNegative ? d : -d } else if let cr = credit { amount = cr }
            }
            guard let amt = amount, !amt.isZero else { skipped.append(n + 1); continue }
            let label = cell(m.labelColumn) ?? ""
            let base = "\(calendar.startOfDay(for: date).timeIntervalSince1970)|\(amt.cents)|\(label)"
            let occ = seen[base, default: 0]; seen[base] = occ + 1
            let fp = fingerprint(date: date, amount: amt, label: label, occurrence: occ, calendar: calendar)
            if known.contains(fp) { dup += 1; continue }
            known.insert(fp)
            txs.append(BankTransaction(date: date, label: label, amount: amt, fingerprint: fp))
        }
        return CSVImportResult(transactions: txs, duplicates: dup, skippedLines: skipped, mapping: m)
    }
}

extension Ledger {
    /// Ajoute les transactions importées (doublons déjà filtrés) et renvoie le nombre ajouté.
    @discardableResult
    public mutating func addImported(_ txs: [BankTransaction]) -> Int {
        let known = Set(transactions.map(\.fingerprint))
        let fresh = txs.filter { !known.contains($0.fingerprint) }
        transactions.append(contentsOf: fresh)
        return fresh.count
    }

    /// Crée une dépense payée depuis une opération de débit.
    public mutating func expense(fromTransaction id: UUID, category: ExpenseCategory) throws {
        guard let i = transactions.firstIndex(where: { $0.id == id }) else { throw LedgerError.notFound }
        guard !transactions[i].isLinked else { throw LedgerError.duplicate }
        let t = transactions[i]
        guard t.amount.isNegative else { throw LedgerError.nonPositiveAmount }
        var e = Expense(date: t.date, amount: -t.amount, category: category, status: .paid)
        e.supplier = t.label; e.transactionId = t.id
        expenses.append(e)
        transactions[i].linkedExpenseId = e.id
    }

    /// Rapproche un crédit bancaire d'une facture (enregistre le paiement).
    public mutating func match(transaction id: UUID, toInvoice invoiceId: UUID) throws {
        guard let t = transactions.first(where: { $0.id == id }) else { throw LedgerError.notFound }
        guard !t.isLinked else { throw LedgerError.duplicate }
        guard t.amount.isPositive else { throw LedgerError.nonPositiveAmount }
        var p = Payment(date: t.date, amount: t.amount)
        p.transactionId = t.id
        p.note = t.label
        try recordPayment(invoiceId: invoiceId, payment: p)
    }
}

// MARK: - Relances

public enum ReminderComposer {
    public static func message(for inv: Invoice, profile: BusinessProfile, contactName: String, today: Date, calendar: Calendar = .fr) -> (subject: String, body: String) {
        let late = inv.daysLate(on: today, calendar: calendar)
        let df: (Date) -> String = { $0.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "fr_FR"))) }
        let number = inv.number ?? ""
        let hello = contactName.isEmpty ? "Bonjour," : "Bonjour \(contactName),"
        let firmness = inv.lastReminderDate == nil
            ? "Sauf erreur de ma part, la facture \(number) du \(df(inv.issueDate)), d'un montant de \(inv.totals.ttc), arrivée à échéance le \(df(inv.dueDate)), n'a pas encore été réglée."
            : "Je reviens vers vous au sujet de la facture \(number) du \(df(inv.issueDate)), échue depuis \(late) jours. Le solde restant dû est de \(inv.balance)."
        let partial = inv.paidAmount.isPositive ? "\n\nJ'ai bien reçu \(inv.paidAmount) ; il reste \(inv.balance) à régler." : ""
        let bank = profile.iban.isEmpty ? "" : "\n\nPour rappel, mes coordonnées bancaires : IBAN \(profile.iban)\(profile.bic.isEmpty ? "" : " — BIC \(profile.bic)")."
        let body = """
        \(hello)

        \(firmness)\(partial)

        Pourriez-vous me confirmer la date de règlement prévue ? Je vous joins à nouveau la facture.\(bank)

        \(profile.latePenaltyText)

        Merci par avance et bonne journée,
        \(profile.ownerName.ifEmpty(profile.displayName))
        """
        return ("Facture \(number) — échéance dépassée", body)
    }
}

// MARK: - Instantané pour le widget

/// Données minimales partagées avec le widget : pas de détail client au-delà du nécessaire.
public struct WidgetSnapshot: Codable, Hashable, Sendable {
    public struct Item: Codable, Hashable, Sendable, Identifiable {
        public var id: String
        public var title: String
        public var amount: Money
        public var date: Date
        public var isAlert: Bool
        public init(id: String, title: String, amount: Money, date: Date, isAlert: Bool) {
            self.id = id; self.title = title; self.amount = amount; self.date = date; self.isAlert = isAlert
        }
    }
    public var generatedAt: Date
    public var monthLabel: String
    public var available: Money
    public var toReserve: Money
    public var collectedMonth: Money
    public var receivables: Money
    public var overdueCount: Int
    public var cashBalance: Money
    public var cashFree: Money
    public var nextDeadline: Item?
    public var deadlines: [Item]
    public var pendingInvoices: [Item]
    /// Solde reconstitué sur les 30 derniers jours (un point par semaine environ).
    public var recentBalances: [Money]
    public var isEmpty: Bool

    public static let placeholder = WidgetSnapshot(
        generatedAt: Date(), monthLabel: "Octobre", available: Money(euros: 4547), toReserve: Money(euros: 2291),
        collectedMonth: Money(euros: 7450), receivables: Money(euros: 4150), overdueCount: 2, cashBalance: Money(euros: 18940),
        cashFree: Money(euros: 10320), nextDeadline: Item(id: "u", title: "URSSAF T3", amount: Money(euros: 4954), date: Date().addingTimeInterval(86400 * 12), isAlert: true),
        deadlines: [Item(id: "u", title: "URSSAF T3", amount: Money(euros: 4954), date: Date().addingTimeInterval(86400 * 12), isAlert: true),
                    Item(id: "c", title: "CFE", amount: Money(euros: 412), date: Date().addingTimeInterval(86400 * 55), isAlert: false)],
        pendingInvoices: [Item(id: "a", title: "Atelier Nord", amount: Money(euros: 2500), date: Date(), isAlert: false),
                          Item(id: "b", title: "Studio Hélice", amount: Money(euros: 1200), date: Date(), isAlert: true)],
        recentBalances: [14200, 15100, 14800, 16900, 18940].map { Money(euros: $0) }, isEmpty: false)

    public static func make(from ledger: Ledger, today: Date, calendar: Calendar = .fr) -> WidgetSnapshot {
        let fin = FinanceEngine(ledger: ledger, today: today, calendar: calendar)
        let month = Period.month(of: today, calendar: calendar)
        let d = fin.dashboard(period: month)
        let soon = calendar.date(byAdding: .day, value: 14, to: today)!
        let toItem: (Deadline) -> Item = { Item(id: $0.id, title: $0.title, amount: $0.amount, date: $0.date, isAlert: $0.date <= soon) }
        let deadlines = d.upcoming.filter { if case .obligation = $0.kind { return true }; return $0.kind == .expense }.prefix(4).map(toItem)
        // L'échéance « importante » est une obligation fiscale ou sociale, pas un abonnement.
        let important = d.upcoming.first { if case .obligation = $0.kind { return $0.amount.isPositive }; return false }.map(toItem)
        let pending = d.receivableInvoices.prefix(4).map {
            Item(id: $0.id.uuidString, title: fin.clientName($0), amount: $0.balance, date: $0.dueDate, isAlert: $0.status(on: today, calendar: calendar) == .overdue)
        }
        let trace = d.cash.balanceTrace
        let balances: [Money] = (0...4).map { w in
            let at = calendar.date(byAdding: .day, value: -7 * (4 - w), to: today)!
            return trace.filter { $0.date <= at }.sum(\.amount)
        }
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "LLLL"
        return WidgetSnapshot(generatedAt: today, monthLabel: f.string(from: today).capitalized, available: d.available, toReserve: d.reserves.total,
                              collectedMonth: d.collected, receivables: d.receivables, overdueCount: d.overdueInvoices.count,
                              cashBalance: d.cash.balance, cashFree: d.cash.free, nextDeadline: important ?? deadlines.first,
                              deadlines: Array(deadlines), pendingInvoices: Array(pending), recentBalances: balances,
                              isEmpty: ledger.invoices.isEmpty && ledger.expenses.isEmpty)
    }
}
