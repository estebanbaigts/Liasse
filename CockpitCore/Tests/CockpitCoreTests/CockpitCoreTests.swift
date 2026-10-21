import Foundation
import Testing
@testable import CockpitCore

let cal = Calendar.fr
func d(_ y: Int, _ m: Int, _ day: Int) -> Date { cal.date(y, m, day) }
func eur(_ s: String) -> Money { MoneyFormat.parse(s)! }

/// Profil BNC SSI trimestriel complet, sans versement libératoire.
func baseLedger() -> Ledger {
    var l = Ledger()
    l.profile.ownerName = "Test"
    l.profile.address = "1 rue Test"
    l.profile.siret = "12345678900012"
    l.profile.activity = .liberaleSSI
    l.profile.activityStart = d(2025, 1, 1)
    l.profile.urssafPeriodicity = .quarterly
    l.profile.openingBalance = .zero
    l.profile.openingBalanceDate = d(2025, 12, 31)
    let c = Client(name: "Client A")
    l.clients = [c]
    return l
}

@discardableResult
func addIssued(_ l: inout Ledger, amount: String, issued: Date, due: Date) -> UUID {
    var inv = Invoice(clientId: l.clients[0].id, issueDate: issued, dueDate: due)
    inv.lines = [DocumentLine(label: "Prestation", quantity: 1, unit: .flat, unitPrice: eur(amount))]
    l.invoices.append(inv)
    try! l.issueInvoice(id: inv.id, on: issued)
    return inv.id
}

@Suite("Montants") struct MoneyTests {
    @Test func parsing() {
        #expect(MoneyFormat.parse("1 234,56 €") == Money(cents: 123456))
        #expect(MoneyFormat.parse("1.234,56") == Money(cents: 123456))
        #expect(MoneyFormat.parse("1,234.56") == Money(cents: 123456))
        #expect(MoneyFormat.parse("-12,5") == Money(cents: -1250))
        #expect(MoneyFormat.parse("(30,00)") == Money(cents: -3000))
        #expect(MoneyFormat.parse("abc") == nil)
        #expect(MoneyFormat.parse("") == nil)
    }
    @Test func roundingHalfUp() {
        // 0,05 × 25,6 % = 0,0128 → 0,01 ; 1,25 × 50 % = 0,625 → 0,63
        #expect(Money(cents: 5).applying(rate: Decimal(string: "0.256")!) == Money(cents: 1))
        #expect(Money(cents: 125).applying(rate: Decimal(string: "0.5")!) == Money(cents: 63))
        #expect(Money(euros: 7450).applying(rate: Decimal(string: "0.256")!) == eur("1907,20"))
    }
    @Test func noFloatDrift() {
        let sum = (0..<1000).reduce(Money.zero) { acc, _ in acc + Money(cents: 10) }
        #expect(sum == Money(euros: 100))
    }
    @Test func quantities() {
        #expect(Money(euros: 600).times(Decimal(string: "2.5")!) == Money(euros: 1500))
    }
}

@Suite("Documents") struct DocumentTests {
    @Test func totalsWithVATAndDiscount() {
        let lines = [DocumentLine(label: "A", quantity: 2, unit: .day, unitPrice: Money(euros: 500), vatRate: Decimal(string: "0.2")!),
                     DocumentLine(label: "B", quantity: 1, unit: .unit, unitPrice: Money(euros: 100), vatRate: Decimal(string: "0.055")!)]
        let t = DocumentTotals.compute(lines: lines, discount: Money(euros: 110), vatApplicable: true)
        #expect(t.grossHT == Money(euros: 1100))
        #expect(t.netHT == Money(euros: 990))
        // remise répartie : 100 € sur la base 20 %, 10 € sur la base 5,5 %
        #expect(t.vat == eur("180") + eur("4,95"))
        #expect(t.ttc == eur("1174,95"))
    }
    @Test func franchiseHasNoVAT() {
        let lines = [DocumentLine(label: "A", quantity: 1, unit: .day, unitPrice: Money(euros: 500), vatRate: Decimal(string: "0.2")!)]
        let t = DocumentTotals.compute(lines: lines, discount: .zero, vatApplicable: false)
        #expect(t.vat == .zero && t.ttc == Money(euros: 500))
    }
    @Test func discountCannotExceedTotal() {
        let lines = [DocumentLine(label: "A", quantity: 1, unit: .flat, unitPrice: Money(euros: 100))]
        #expect(DocumentTotals.compute(lines: lines, discount: Money(euros: 500), vatApplicable: false).ttc == .zero)
    }
}

@Suite("Facturation") struct InvoicingTests {
    @Test func numberingIsSequentialAndNeverReused() throws {
        var l = baseLedger()
        let a = addIssued(&l, amount: "100", issued: d(2026, 1, 5), due: d(2026, 2, 5))
        let b = addIssued(&l, amount: "200", issued: d(2026, 1, 6), due: d(2026, 2, 6))
        #expect(l.invoice(a)?.number == "F-2026-0001")
        #expect(l.invoice(b)?.number == "F-2026-0002")
        // Un brouillon supprimé ne consomme pas de numéro ; une annulation ne libère pas le sien.
        var draft = Invoice(clientId: l.clients[0].id, issueDate: d(2026, 1, 7), dueDate: d(2026, 2, 7))
        draft.lines = [DocumentLine(label: "x", quantity: 1, unit: .flat, unitPrice: Money(euros: 1))]
        l.invoices.append(draft)
        try l.deleteDraft(id: draft.id)
        let credit = try l.cancelInvoice(id: b, on: d(2026, 1, 8), reason: "Erreur")
        #expect(credit.number == "A-2026-0001")
        let c = addIssued(&l, amount: "300", issued: d(2026, 1, 9), due: d(2026, 2, 9))
        #expect(l.invoice(c)?.number == "F-2026-0003")
        // Nouvelle année : nouvelle séquence
        let n = addIssued(&l, amount: "300", issued: d(2027, 1, 2), due: d(2027, 2, 2))
        #expect(l.invoice(n)?.number == "F-2027-0001")
    }

    @Test func issuedInvoiceCannotBeDeletedOrReissued() throws {
        var l = baseLedger()
        let a = addIssued(&l, amount: "100", issued: d(2026, 1, 5), due: d(2026, 2, 5))
        #expect(throws: LedgerError.invoiceNotDraft) { try l.deleteDraft(id: a) }
        #expect(throws: LedgerError.invoiceNotDraft) { try l.issueInvoice(id: a, on: d(2026, 1, 6)) }
    }

    @Test func issuanceRequiresIssuerInfo() {
        var l = baseLedger()
        l.profile.siret = "123"
        var inv = Invoice(clientId: l.clients[0].id, issueDate: d(2026, 1, 5), dueDate: d(2026, 2, 5))
        inv.lines = [DocumentLine(label: "x", quantity: 1, unit: .flat, unitPrice: Money(euros: 1))]
        l.invoices.append(inv)
        #expect(throws: LedgerError.missingIssuerInfo(["SIRET (14 chiffres)"])) { try l.issueInvoice(id: inv.id, on: d(2026, 1, 5)) }
        #expect(l.counters.isEmpty)
    }

    @Test func lineWithoutLabelBlocksIssuance() {
        var l = baseLedger()
        var inv = Invoice(clientId: l.clients[0].id, issueDate: d(2026, 1, 5), dueDate: d(2026, 2, 5))
        inv.lines = [DocumentLine(label: "  ", quantity: 1, unit: .day, unitPrice: Money(euros: 500))]
        l.invoices.append(inv)
        #expect(throws: LedgerError.lineWithoutLabel) { try l.issueInvoice(id: inv.id, on: d(2026, 1, 5)) }
        #expect(l.counters.isEmpty)
    }

    @Test func legalMentionsFrozenAtIssue() throws {
        var l = baseLedger()
        let a = addIssued(&l, amount: "100", issued: d(2026, 1, 5), due: d(2026, 2, 5))
        #expect(l.invoice(a)!.legalMentions.contains("TVA non applicable, art. 293 B du CGI"))
        l.clients[0].name = "Nouveau nom"
        #expect(l.invoice(a)!.clientSnapshot?.name == "Client A")
    }

    @Test func partialPaymentsAndStatuses() throws {
        var l = baseLedger()
        let a = addIssued(&l, amount: "1000", issued: d(2026, 3, 1), due: d(2026, 3, 31))
        #expect(l.invoice(a)!.status(on: d(2026, 3, 10)) == .issued)
        try l.recordPayment(invoiceId: a, payment: Payment(date: d(2026, 3, 10), amount: Money(euros: 400)))
        #expect(l.invoice(a)!.status(on: d(2026, 3, 10)) == .partiallyPaid)
        #expect(l.invoice(a)!.balance == Money(euros: 600))
        #expect(l.invoice(a)!.status(on: d(2026, 4, 2)) == .overdue)
        #expect(l.invoice(a)!.daysLate(on: d(2026, 4, 2)) == 2)
        #expect(throws: LedgerError.paymentExceedsBalance(balance: Money(euros: 600))) {
            try l.recordPayment(invoiceId: a, payment: Payment(date: d(2026, 4, 3), amount: Money(euros: 601)))
        }
        try l.recordPayment(invoiceId: a, payment: Payment(date: d(2026, 4, 3), amount: Money(euros: 600)))
        #expect(l.invoice(a)!.status(on: d(2026, 4, 3)) == .paid)
        #expect(throws: LedgerError.paymentExceedsBalance(balance: .zero)) {
            try l.recordPayment(invoiceId: a, payment: Payment(date: d(2026, 4, 3), amount: Money(cents: 1)))
        }
    }

    @Test func draftPaymentsRejected() {
        var l = baseLedger()
        let inv = Invoice(clientId: l.clients[0].id, issueDate: d(2026, 3, 1), dueDate: d(2026, 3, 31))
        l.invoices.append(inv)
        #expect(throws: LedgerError.invoiceNotIssued) { try l.recordPayment(invoiceId: inv.id, payment: Payment(date: d(2026, 3, 2), amount: Money(euros: 1))) }
    }

    @Test func cancellationCreatesCreditNoteAndNetsInvoiced() throws {
        var l = baseLedger()
        let a = addIssued(&l, amount: "1000", issued: d(2026, 3, 1), due: d(2026, 3, 31))
        try l.cancelInvoice(id: a, on: d(2026, 3, 5), reason: "Mission annulée")
        #expect(l.invoice(a)!.status(on: d(2026, 3, 5)) == .cancelled)
        let fin = FinanceEngine(ledger: l, today: d(2026, 3, 20))
        #expect(fin.invoiced(in: .month(of: d(2026, 3, 1))).0 == .zero)
        #expect(fin.openInvoices.isEmpty)
        #expect(fin.dashboard(period: .month(of: d(2026, 3, 1))).receivables == .zero)
    }

    @Test func quoteConversion() throws {
        var l = baseLedger()
        var q = Quote(clientId: l.clients[0].id, issueDate: d(2026, 3, 1), validUntil: d(2026, 4, 1))
        q.lines = [DocumentLine(label: "Forfait", quantity: 1, unit: .flat, unitPrice: Money(euros: 2400))]
        l.quotes.append(q)
        try l.finalizeQuote(id: q.id, on: d(2026, 3, 1))
        #expect(l.quotes[0].number == "D-2026-0001")
        #expect(throws: LedgerError.quoteNotAccepted) { try l.convertQuote(id: q.id, on: d(2026, 3, 2)) }
        l.quotes[0].status = .accepted
        let inv = try l.convertQuote(id: q.id, on: d(2026, 3, 2))
        #expect(inv.lifecycle == .draft && inv.number == nil)
        #expect(inv.totals.ttc == Money(euros: 2400))
        #expect(throws: LedgerError.alreadyInvoiced) { try l.convertQuote(id: q.id, on: d(2026, 3, 2)) }
        // Le brouillon issu du devis n'est pas compté comme facturé.
        #expect(FinanceEngine(ledger: l, today: d(2026, 3, 3)).invoiced(in: .month(of: d(2026, 3, 1))).0 == .zero)
    }

    @Test func reminderMentionsBalance() throws {
        var l = baseLedger()
        let a = addIssued(&l, amount: "1200", issued: d(2026, 9, 2), due: d(2026, 10, 3))
        try l.recordPayment(invoiceId: a, payment: Payment(date: d(2026, 10, 5), amount: Money(euros: 200)))
        let m = ReminderComposer.message(for: l.invoice(a)!, profile: l.profile, contactName: "Camille", today: d(2026, 10, 21))
        #expect(m.subject.contains("F-2026-0001"))
        #expect(m.body.contains("Bonjour Camille"))
        #expect(m.body.contains(Money(euros: 1000).description))
    }
}

@Suite("Règles fiscales") struct TaxTests {
    @Test func catalogueValuesAndSources() {
        let r = TaxRuleSet.defaultCatalogue
        #expect(r.rule(.cotisations, activity: .liberaleSSI, artisan: false, on: d(2026, 5, 1))?.value == Decimal(string: "0.256"))
        #expect(r.rule(.cotisations, activity: .prestationsBIC, artisan: false, on: d(2026, 5, 1))?.value == Decimal(string: "0.212"))
        #expect(r.rule(.cotisations, activity: .venteMarchandises, artisan: false, on: d(2026, 5, 1))?.value == Decimal(string: "0.123"))
        #expect(r.rule(.cotisations, activity: .liberaleCipav, artisan: false, on: d(2026, 5, 1))?.value == Decimal(string: "0.232"))
        #expect(r.rule(.cfp, activity: .prestationsBIC, artisan: true, on: d(2026, 5, 1))?.value == Decimal(string: "0.003"))
        #expect(r.rule(.cfp, activity: .prestationsBIC, artisan: false, on: d(2026, 5, 1))?.value == Decimal(string: "0.001"))
        #expect(r.rule(.versementLiberatoire, activity: .liberaleSSI, artisan: false, on: d(2026, 5, 1))?.value == Decimal(string: "0.022"))
        for rule in r.rules {
            #expect(rule.sourceURL.hasPrefix("https://entreprendre.service-public.gouv.fr/"))
            #expect(rule.verifiedOn == d(2026, 10, 21))
        }
    }

    @Test func noRuleBeforeVerifiedPeriod() {
        // Aucune règle 2025 vérifiée : l'app doit dire « à vérifier » au lieu d'inventer.
        #expect(TaxRuleSet.defaultCatalogue.rule(.cotisations, activity: .liberaleSSI, artisan: false, on: d(2025, 6, 1)) == nil)
        var l = baseLedger()
        let a = addIssued(&l, amount: "1000", issued: d(2025, 5, 1), due: d(2025, 5, 31))
        try! l.recordPayment(invoiceId: a, payment: Payment(date: d(2025, 5, 10), amount: Money(euros: 1000)))
        let o = TaxEngine(ledger: l).obligations(year: 2025, today: d(2026, 1, 15)).first { $0.kind == .cotisations && $0.base!.isPositive }!
        #expect(o.status == .toVerify && o.estimated == nil)
    }

    @Test func effectiveDateSelection() {
        var set = TaxRuleSet.defaultCatalogue
        var newer = set.rules.first { $0.id == "cot-ssi-2026" }!
        newer.id = "cot-ssi-2027"; newer.value = Decimal(string: "0.27")!; newer.effectiveFrom = d(2027, 1, 1)
        set.rules.append(newer)
        #expect(set.rule(.cotisations, activity: .liberaleSSI, artisan: false, on: d(2026, 12, 31))?.value == Decimal(string: "0.256"))
        #expect(set.rule(.cotisations, activity: .liberaleSSI, artisan: false, on: d(2027, 1, 1))?.value == Decimal(string: "0.27"))
    }

    @Test func quarterlyCotisationsOnCollectedNotInvoiced() throws {
        var l = baseLedger()
        let a = addIssued(&l, amount: "10000", issued: d(2026, 7, 1), due: d(2026, 7, 31))
        addIssued(&l, amount: "5000", issued: d(2026, 8, 1), due: d(2026, 8, 31)) // jamais payée
        try l.recordPayment(invoiceId: a, payment: Payment(date: d(2026, 8, 3), amount: Money(euros: 6000)))
        try l.recordPayment(invoiceId: a, payment: Payment(date: d(2026, 10, 2), amount: Money(euros: 4000))) // T4
        let obs = TaxEngine(ledger: l).obligations(year: 2026, today: d(2026, 10, 21))
        let t3 = obs.first { $0.kind == .cotisations && $0.period.start == Period.quarter(of: d(2026, 8, 1)).start }!
        #expect(t3.base == Money(euros: 6000))
        #expect(t3.estimated == eur("1536"))
        #expect(t3.status == .toDeclare)
        // 31 octobre 2026 est un samedi → lundi 2 novembre
        #expect(cal.isDate(t3.dueDate, inSameDayAs: d(2026, 11, 2)))
        let t4 = obs.first { $0.kind == .cotisations && $0.period.start == Period.quarter(of: d(2026, 11, 1)).start }!
        #expect(t4.status == .provisional && t4.base == Money(euros: 4000))
        let cfp = obs.first { $0.kind == .cfp && $0.period == t3.period }!
        #expect(cfp.estimated == Money(euros: 12))
    }

    @Test func monthlyDueDatesAndHolidays() {
        var l = baseLedger(); l.profile.urssafPeriodicity = .monthly
        let t = TaxEngine(ledger: l)
        // Mai 2026 → 30 juin (mardi)
        #expect(cal.isDate(t.urssafDueDate(for: .month(of: d(2026, 5, 10))), inSameDayAs: d(2026, 6, 30)))
        // Décembre 2026 → 31 janvier 2027 (dimanche) → 1er février
        #expect(cal.isDate(t.urssafDueDate(for: .month(of: d(2026, 12, 10))), inSameDayAs: d(2027, 2, 1)))
        #expect(FrenchCalendar.isHoliday(d(2026, 5, 25))) // lundi de Pentecôte 2026
        #expect(FrenchCalendar.isHoliday(d(2026, 4, 6)))  // lundi de Pâques 2026
    }

    @Test func declaredAndPaidStatuses() throws {
        var l = baseLedger()
        let a = addIssued(&l, amount: "1000", issued: d(2026, 1, 5), due: d(2026, 1, 31))
        try l.recordPayment(invoiceId: a, payment: Payment(date: d(2026, 1, 20), amount: Money(euros: 1000)))
        let key = TaxEngine(ledger: l).obligations(year: 2026, today: d(2026, 4, 10)).first { $0.kind == .cotisations }!.key
        var r = ObligationRecord(key: key); r.declaredAmount = Money(euros: 260)
        l.updateObligationRecord(r)
        var o = TaxEngine(ledger: l).obligations(year: 2026, today: d(2026, 4, 10)).first { $0.key == key }!
        #expect(o.status == .toPay)
        #expect(o.variance == Money(euros: 4)) // déclaré 260 vs estimé 256
        r.paidAmount = Money(euros: 260); r.paidDate = d(2026, 4, 20)
        l.updateObligationRecord(r)
        o = TaxEngine(ledger: l).obligations(year: 2026, today: d(2026, 4, 21)).first { $0.key == key }!
        #expect(o.status == .paid && o.remaining == .zero)
    }

    @Test func versementLiberatoireReplacesIncomeTaxEstimate() throws {
        var l = baseLedger(); l.profile.versementLiberatoire = true
        let a = addIssued(&l, amount: "1000", issued: d(2026, 1, 5), due: d(2026, 1, 31))
        try l.recordPayment(invoiceId: a, payment: Payment(date: d(2026, 1, 20), amount: Money(euros: 1000)))
        let obs = TaxEngine(ledger: l).obligations(year: 2026, today: d(2026, 2, 1))
        #expect(obs.contains { $0.kind == .versementLiberatoire && $0.estimated == Money(euros: 22) })
        #expect(!obs.contains { $0.kind == .incomeTax })
    }

    @Test func incomeTaxEstimateUsesAllowanceAndUserRate() throws {
        var l = baseLedger(); l.profile.withholdingTaxRate = Decimal(string: "0.075")
        let a = addIssued(&l, amount: "10000", issued: d(2026, 1, 5), due: d(2026, 1, 31))
        try l.recordPayment(invoiceId: a, payment: Payment(date: d(2026, 1, 20), amount: Money(euros: 10000)))
        let ir = TaxEngine(ledger: l).obligations(year: 2026, today: d(2026, 2, 1)).first { $0.kind == .incomeTax }!
        #expect(ir.estimated == eur("495")) // 10 000 × 66 % × 7,5 %
        l.profile.withholdingTaxRate = nil
        let unknown = TaxEngine(ledger: l).obligations(year: 2026, today: d(2026, 2, 1)).first { $0.kind == .incomeTax }!
        #expect(unknown.status == .toVerify && unknown.estimated == nil)
    }

    @Test func cfeExemptFirstYear() {
        var l = baseLedger(); l.profile.activityStart = d(2026, 2, 1); l.profile.cfeAmount = Money(euros: 400)
        #expect(!TaxEngine(ledger: l).obligations(year: 2026, today: d(2026, 6, 1)).contains { $0.kind == .cfe })
        #expect(TaxEngine(ledger: l).obligations(year: 2027, today: d(2027, 6, 1)).contains { $0.kind == .cfe && $0.estimated == Money(euros: 400) })
    }

    @Test func vatOnCollectionsWhenRedevable() throws {
        var l = baseLedger(); l.profile.vatRegime = .redevable; l.profile.vatPeriodicity = .monthly
        var inv = Invoice(clientId: l.clients[0].id, issueDate: d(2026, 3, 1), dueDate: d(2026, 3, 31))
        inv.lines = [DocumentLine(label: "x", quantity: 1, unit: .flat, unitPrice: Money(euros: 1000), vatRate: Decimal(string: "0.2")!)]
        l.invoices.append(inv)
        try l.issueInvoice(id: inv.id, on: d(2026, 3, 1))
        #expect(l.invoice(inv.id)!.totals.ttc == Money(euros: 1200))
        try l.recordPayment(invoiceId: inv.id, payment: Payment(date: d(2026, 3, 15), amount: Money(euros: 600)))
        var e = Expense(date: d(2026, 3, 10), amount: Money(euros: 120), category: .software, status: .paid); e.vatAmount = Money(euros: 20)
        l.expenses.append(e)
        let t = TaxEngine(ledger: l)
        #expect(t.collectedHT(in: .month(of: d(2026, 3, 1))) == Money(euros: 500))
        let vat = t.obligations(year: 2026, today: d(2026, 4, 2)).first { $0.kind == .vat && $0.period == .month(of: d(2026, 3, 1)) }!
        #expect(vat.estimated == Money(euros: 80)) // 100 collectée − 20 déductible
        #expect(!l.invoice(inv.id)!.legalMentions.contains { $0.contains("293 B") })
    }

    @Test func thresholdAlert() throws {
        var l = baseLedger()
        let a = addIssued(&l, amount: "40000", issued: d(2026, 1, 5), due: d(2026, 1, 31))
        try l.recordPayment(invoiceId: a, payment: Payment(date: d(2026, 1, 20), amount: Money(euros: 40000)))
        let alerts = TaxEngine(ledger: l).thresholdAlerts(year: 2026, today: d(2026, 2, 1))
        #expect(alerts.contains { $0.contains("seuil de base") })
    }

    @Test func otherLegalFormsAreNotComputed() {
        var l = baseLedger(); l.profile.legalForm = .sasu
        #expect(TaxEngine(ledger: l).obligations(year: 2026, today: d(2026, 5, 1)).isEmpty)
    }
}

@Suite("Tableau de bord") struct DashboardTests {
    @Test func separatesInvoicedCollectedAndOutstanding() throws {
        var l = baseLedger()
        l.profile.withholdingTaxRate = Decimal(string: "0.075")
        let a = addIssued(&l, amount: "5000", issued: d(2026, 9, 20), due: d(2026, 10, 20))
        let b = addIssued(&l, amount: "4800", issued: d(2026, 10, 2), due: d(2026, 11, 1))
        try l.recordPayment(invoiceId: a, payment: Payment(date: d(2026, 10, 5), amount: Money(euros: 5000)))
        try l.recordPayment(invoiceId: b, payment: Payment(date: d(2026, 10, 15), amount: Money(euros: 2450)))
        l.expenses.append(Expense(date: d(2026, 10, 3), amount: Money(euros: 612), category: .software, status: .paid))
        l.expenses.append(Expense(date: d(2026, 10, 28), amount: Money(euros: 240), category: .software, status: .planned))
        let dash = FinanceEngine(ledger: l, today: d(2026, 10, 21)).dashboard(period: .month(of: d(2026, 10, 1)))
        #expect(dash.invoicedHT == Money(euros: 4800))
        #expect(dash.collected == Money(euros: 7450))
        #expect(dash.receivables == Money(euros: 2350))
        #expect(dash.expensesPaid == Money(euros: 612))
        #expect(dash.expensesPlanned == Money(euros: 240))
        #expect(dash.reserves.cotisations == eur("1907,20"))
        #expect(dash.reserves.cfp == eur("14,90"))
        #expect(dash.reserves.incomeTax == eur("368,78"))
        #expect(dash.available == eur("4547,12"))
        // Les traces expliquent exactement chaque total.
        #expect(dash.collectedTrace.sum(\.amount) == dash.collected)
        #expect(dash.invoicedTrace.sum(\.amount) == dash.invoicedHT)
    }

    @Test func recurringPlannedExpenses() {
        var l = baseLedger()
        var e = Expense(date: d(2026, 10, 11), amount: Money(euros: 89), category: .software, status: .planned)
        e.recurrence = .monthly
        l.expenses = [e]
        let fin = FinanceEngine(ledger: l, today: d(2026, 10, 1))
        #expect(fin.plannedOccurrences(in: Period(start: d(2026, 10, 1), end: d(2027, 1, 31))).count == 4)
        l.markExpensePaid(id: e.id, on: d(2026, 10, 11))
        #expect(l.expenses.count == 2)
        #expect(l.expenses.first { $0.status == .paid }?.amount == Money(euros: 89))
        #expect(cal.isDate(l.expenses.first { $0.id == e.id }!.date, inSameDayAs: d(2026, 11, 11)))
    }

    @Test func cashPositionReconstructsBalance() throws {
        var l = baseLedger()
        l.profile.openingBalance = Money(euros: 1000); l.profile.openingBalanceDate = d(2026, 9, 30)
        let a = addIssued(&l, amount: "2000", issued: d(2026, 10, 1), due: d(2026, 10, 30))
        try l.recordPayment(invoiceId: a, payment: Payment(date: d(2026, 10, 10), amount: Money(euros: 2000)))
        l.expenses.append(Expense(date: d(2026, 10, 12), amount: Money(euros: 100), category: .bank, status: .paid))
        l.expenses.append(Expense(date: d(2026, 10, 25), amount: Money(euros: 999), category: .bank, status: .planned))
        let cash = FinanceEngine(ledger: l, today: d(2026, 10, 21)).cashPosition()
        #expect(cash.balance == Money(euros: 2900))
        #expect(cash.reservesOutstanding == eur("516")) // 25,6 % + 0,2 % de 2 000
        #expect(cash.free == eur("2384"))
    }

    @Test func movementsOnOpeningDayAreIncluded() throws {
        var l = baseLedger()
        l.profile.openingBalance = Money(euros: 100); l.profile.openingBalanceDate = d(2026, 10, 21)
        let a = addIssued(&l, amount: "500", issued: d(2026, 10, 21), due: d(2026, 11, 20))
        try l.recordPayment(invoiceId: a, payment: Payment(date: d(2026, 10, 21), amount: Money(euros: 200)))
        #expect(FinanceEngine(ledger: l, today: d(2026, 10, 21)).cashPosition().balance == Money(euros: 300))
        // Un paiement daté dans le futur n'est pas encore sur le compte.
        try l.recordPayment(invoiceId: a, payment: Payment(date: d(2026, 10, 25), amount: Money(euros: 100)))
        #expect(FinanceEngine(ledger: l, today: d(2026, 10, 21)).cashPosition().balance == Money(euros: 300))
    }
}

@Suite("Prévisions") struct ForecastTests {
    func ledger() throws -> Ledger {
        var l = baseLedger()
        l.profile.openingBalance = Money(euros: 5000); l.profile.openingBalanceDate = d(2026, 10, 1)
        addIssued(&l, amount: "3000", issued: d(2026, 10, 1), due: d(2026, 10, 31)) // pas encore due
        addIssued(&l, amount: "1000", issued: d(2026, 8, 1), due: d(2026, 8, 31))   // 51 j de retard
        var e = Expense(date: d(2026, 11, 15), amount: Money(euros: 500), category: .software, status: .planned)
        e.recurrence = .none
        l.expenses.append(e)
        return l
    }

    @Test func scenariosOrderAndNoDoubleCounting() throws {
        let l = try ledger()
        let fe = ForecastEngine(finance: FinanceEngine(ledger: l, today: d(2026, 10, 21)))
        let o = fe.run(.optimistic), r = fe.run(.realistic), p = fe.run(.prudent)
        #expect(o.start == Money(euros: 5000))
        // Le départ est le solde réel : aucune facture impayée n'y est ajoutée.
        #expect(o.points[0].balance == Money(euros: 5000))
        #expect(o.balance(at: 90) >= r.balance(at: 90))
        #expect(r.balance(at: 90) >= p.balance(at: 90))
        // Prudent : la facture en retard est exclue
        #expect(!p.events.contains { $0.amount == Money(euros: 1000) })
        // Chaque facture ouverte apparaît au plus une fois
        let receivables = o.events.filter { $0.kind == .receivable }
        #expect(receivables.count == 2)
        #expect(o.events.contains { $0.kind == .expense && $0.amount == Money(euros: -500) })
    }

    @Test func lowPointAndThreshold() throws {
        var l = try ledger()
        l.profile.openingBalance = Money(euros: 300)
        var fe = ForecastEngine(finance: FinanceEngine(ledger: l, today: d(2026, 10, 21)))
        fe.assumptions.safetyThreshold = .zero
        let p = fe.run(.prudent)
        #expect(p.low.balance < .zero)
        #expect(p.firstBelowThreshold != nil)
    }
}

@Suite("Recommandations") struct InsightTests {
    @Test func overdueAndReserveInsightsAreTraceable() throws {
        let l = SampleData.ledger(today: d(2026, 10, 21))
        let fin = FinanceEngine(ledger: l, today: d(2026, 10, 21))
        let ins = InsightEngine(finance: fin, forecast: ForecastEngine(finance: fin)).insights()
        let overdue = try #require(ins.first { $0.id == "overdue" })
        #expect(overdue.title.contains("2 factures"))
        #expect(!overdue.figures.isEmpty && !overdue.assumptions.isEmpty)
        #expect(ins.contains { $0.id == "reserve" })
        // Classement : urgence décroissante
        #expect(zip(ins, ins.dropFirst()).allSatisfy { $0.urgency >= $1.urgency })
    }
}

@Suite("Import CSV") struct CSVTests {
    let sample = """
    Date;Libellé;Débit;Crédit
    18/10/2026;VIR ATELIER NORD;;2 400,00
    20/10/2026;CB FIGMA;89,00;
    20/10/2026;CB FIGMA;89,00;
    pas une date;x;1;
    """

    @Test func parsesDebitCreditAndKeepsSameDayDuplicatesInFile() {
        let r = CSVImporter.parse(sample, existing: [])!
        #expect(r.transactions.count == 3)
        #expect(r.transactions[0].amount == Money(euros: 2400))
        #expect(r.transactions[1].amount == Money(euros: -89))
        #expect(r.skippedLines == [5])
    }

    @Test func reimportIsDeduplicated() {
        var l = Ledger()
        let first = CSVImporter.parse(sample, existing: [])!
        #expect(l.addImported(first.transactions) == 3)
        let again = CSVImporter.parse(sample, existing: Set(l.transactions.map(\.fingerprint)))!
        #expect(again.transactions.isEmpty && again.duplicates == 3)
    }

    @Test func signedAmountColumnAndCommaDelimiter() {
        let csv = "date,label,amount\n2026-10-01,Client,1500.50\n2026-10-02,Bank fee,-3.20\n"
        let r = CSVImporter.parse(csv, existing: [])!
        #expect(r.transactions.map(\.amount) == [Money(cents: 150050), Money(cents: -320)])
    }

    @Test func matchingCreatesPaymentOnce() throws {
        var l = baseLedger()
        let a = addIssued(&l, amount: "2400", issued: d(2026, 10, 1), due: d(2026, 10, 31))
        l.addImported(CSVImporter.parse(sample, existing: [])!.transactions)
        let credit = l.transactions[0]
        try l.match(transaction: credit.id, toInvoice: a)
        #expect(l.invoice(a)!.balance == .zero)
        #expect(throws: LedgerError.duplicate) { try l.match(transaction: credit.id, toInvoice: a) }
        try l.expense(fromTransaction: l.transactions[1].id, category: .software)
        #expect(l.expenses.count == 1 && l.expenses[0].amount == Money(euros: 89))
    }
}

@Suite("Persistance") struct PersistenceTests {
    func tempStore() throws -> LedgerStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cockpit-tests-\(UUID().uuidString)")
        return try LedgerStore(directory: dir)
    }

    @Test func roundTripPreservesExactValues() throws {
        let store = try tempStore()
        let l = SampleData.ledger(today: d(2026, 10, 21))
        try store.save(l)
        let loaded = try store.load()
        #expect(loaded == l)
        #expect(loaded.rules.rules.first { $0.id == "cot-ssi-2026" }?.value == Decimal(string: "0.256"))
        let attrs = try FileManager.default.attributesOfItem(atPath: store.dataURL.path)
        #expect((attrs[.posixPermissions] as? Int) == 0o600)
    }

    @Test func backupAndRestore() throws {
        let store = try tempStore()
        var l = SampleData.ledger(today: d(2026, 10, 21))
        try store.save(l)
        let backup = try store.backupNow(l)
        l.clients.removeAll()
        try store.save(l)
        #expect(try store.load().clients.isEmpty)
        let restored = try store.restore(from: backup)
        #expect(restored.clients.count == 4)
        #expect(try store.load().clients.count == 4)
        // L'état remplacé a été sauvegardé avant la restauration.
        #expect(store.backups().contains { $0.url.lastPathComponent.contains("avant-restauration") })
    }

    @Test func invalidBackupDoesNotOverwrite() throws {
        let store = try tempStore()
        try store.save(SampleData.ledger(today: d(2026, 10, 21)))
        let bad = store.directory.appendingPathComponent("bad.json")
        try Data("{nope".utf8).write(to: bad)
        #expect(throws: StoreError.self) { try store.restore(from: bad) }
        #expect(try store.load().clients.count == 4)
    }

    @Test func migrationFromV0WithBackup() throws {
        let store = try tempStore()
        // v0 : pas de schemaVersion, pas de compteurs, profil incomplet.
        let v0: [String: Any] = ["profile": ["ownerName": "Ancien"], "rules": try JSONSerialization.jsonObject(with: LedgerStore.encoder().encode(TaxRuleSet.defaultCatalogue))]
        try JSONSerialization.data(withJSONObject: v0).write(to: store.dataURL)
        let l = try store.load()
        #expect(l.schemaVersion == Ledger.currentSchemaVersion)
        #expect(l.profile.ownerName == "Ancien")
        #expect(l.profile.paymentTermDays == 30)
        #expect(store.backups().contains { $0.url.lastPathComponent.contains("avant-migration-v0") })
    }

    @Test func newerSchemaIsRefused() throws {
        let store = try tempStore()
        try Data(#"{"schemaVersion": 99}"#.utf8).write(to: store.dataURL)
        #expect(throws: StoreError.self) { try store.load() }
    }

    @Test func widgetSnapshotMatchesDashboard() throws {
        let l = SampleData.ledger(today: d(2026, 10, 21))
        let s = WidgetSnapshot.make(from: l, today: d(2026, 10, 21))
        let dash = FinanceEngine(ledger: l, today: d(2026, 10, 21)).dashboard(period: .month(of: d(2026, 10, 21)))
        #expect(s.available == dash.available)
        #expect(s.toReserve == dash.reserves.total)
        #expect(s.receivables == dash.receivables)
        #expect(s.overdueCount == 2)
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(WidgetSnapshot.self, from: data) == s)
    }
}
