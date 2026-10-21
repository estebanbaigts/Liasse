import Foundation

/// Données d'exemple clairement fictives, pour découvrir l'app. Jamais chargées sans action de l'utilisateur.
public enum SampleData {
    public static func ledger(today: Date, calendar cal: Calendar = .fr) -> Ledger {
        var l = Ledger()
        let y = cal.component(.year, from: today)
        func ago(_ d: Int) -> Date { cal.date(byAdding: .day, value: -d, to: cal.date(bySettingHour: 12, minute: 0, second: 0, of: today)!)! }
        func inDays(_ d: Int) -> Date { ago(-d) }

        var p = BusinessProfile()
        p.ownerName = "Alex Martin (exemple)"
        p.tradeName = ""
        p.activity = .liberaleSSI
        p.activityStart = cal.date(y - 1, 9, 1)
        p.urssafPeriodicity = .quarterly
        p.withholdingTaxRate = Decimal(string: "0.075")
        p.cfeAmount = Money(euros: 412)
        p.address = "12 rue de l'Exemple\n75011 Paris"
        p.email = "alex@exemple.fr"
        p.siret = "12345678900012"
        p.iban = "FR76 0000 0000 0000 0000 0000 000"
        p.monthlyRevenueGoal = Money(euros: 9000)
        p.defaultDailyRate = Money(euros: 550)
        p.openingBalance = Money(euros: 9_200)
        p.openingBalanceDate = ago(120)
        p.onboardingCompleted = true
        l.profile = p

        let nord = Client(name: "Atelier Nord")
        var helice = Client(name: "Studio Hélice"); helice.contactName = "Camille"; helice.email = "compta@helice.example"
        let ferrand = Client(name: "Maison Ferrand")
        let ostral = Client(name: "Groupe Ostral")
        l.clients = [nord, helice, ferrand, ostral]
        for i in l.clients.indices { l.clients[i].address = "Adresse fictive\n69000 Lyon"; l.clients[i].createdAt = ago(300) }

        var m1 = Mission(title: "Refonte du site", clientId: nord.id, dailyRate: Money(euros: 600))
        m1.plannedDays = 20; m1.workedDays = 16; m1.startDate = ago(70)
        var m2 = Mission(title: "Audit produit", clientId: ostral.id, dailyRate: Money(euros: 650))
        m2.plannedDays = 10; m2.workedDays = 10; m2.status = .done; m2.fees = Money(euros: 180)
        l.missions = [m1, m2]

        func invoice(_ c: Client, _ issued: Int, term: Int = 30, days: Decimal, rate: Int, label: String, mission: UUID? = nil, paid: [(Int, Int)] = []) {
            var inv = Invoice(clientId: c.id, issueDate: ago(issued), dueDate: ago(issued - term))
            inv.lines = [DocumentLine(label: label, quantity: days, unit: .day, unitPrice: Money(euros: rate))]
            inv.missionId = mission
            l.invoices.append(inv)
            _ = try? l.issueInvoice(id: inv.id, on: ago(issued))
            for (d, amount) in paid { try? l.recordPayment(invoiceId: inv.id, payment: Payment(date: ago(d), amount: Money(euros: amount))) }
        }
        invoice(ostral, 110, days: 5, rate: 650, label: "Audit produit — phase 1", mission: m2.id, paid: [(78, 3250)])
        invoice(nord, 95, days: 6, rate: 600, label: "Refonte du site — cadrage", mission: m1.id, paid: [(60, 3600)])
        invoice(ostral, 60, days: 5, rate: 650, label: "Audit produit — phase 2", mission: m2.id, paid: [(18, 3250)])
        invoice(helice, 49, days: 2, rate: 600, label: "Atelier UX", paid: [])
        invoice(nord, 40, days: 7, rate: 600, label: "Refonte du site — design", mission: m1.id, paid: [(5, 2400), (3, 1800)])
        invoice(ferrand, 34, days: 1.5, rate: 300, label: "Conseil éditorial")
        invoice(nord, 6, days: 4, rate: 625, label: "Refonte du site — intégration", mission: m1.id)

        var q = Quote(clientId: ferrand.id, issueDate: ago(3), validUntil: inDays(27))
        q.lines = [DocumentLine(label: "Accompagnement éditorial (forfait)", quantity: 1, unit: .flat, unitPrice: Money(euros: 2400))]
        l.quotes.append(q)
        try? l.finalizeQuote(id: q.id, on: ago(3))

        func expense(_ d: Int, _ amount: Int, _ cat: ExpenseCategory, _ supplier: String, status: ExpenseStatus = .paid, rec: Recurrence = .none, created: Int? = nil) {
            var e = Expense(date: d >= 0 ? ago(d) : inDays(-d), amount: Money(euros: amount), category: cat, status: status)
            e.supplier = supplier; e.recurrence = rec; e.createdAt = ago(created ?? max(d, 0))
            l.expenses.append(e)
        }
        expense(50, 89, .software, "Figma"); expense(20, 89, .software, "Figma")
        expense(44, 120, .travel, "SNCF"); expense(12, 214, .travel, "SNCF")
        expense(15, 1299, .hardware, "Écran")
        expense(9, 34, .telecom, "Opérateur"); expense(39, 34, .telecom, "Opérateur")
        expense(4, 46, .meals, "Déjeuner client")
        expense(-11, 89, .software, "Figma", status: .planned, rec: .monthly, created: 280)
        expense(-43, 240, .software, "Logiciel de compta", status: .planned, rec: .yearly, created: 300)
        expense(-20, 34, .telecom, "Opérateur", status: .planned, rec: .monthly, created: 40)

        // Le trimestre précédent a été déclaré et payé.
        let tax = TaxEngine(ledger: l, calendar: cal)
        for o in (tax.obligations(year: y - 1, today: today) + tax.obligations(year: y, today: today)) where (o.kind == .cotisations || o.kind == .cfp || o.kind == .incomeTax) && o.dueDate < today {
            var r = ObligationRecord(key: o.key)
            r.declaredAmount = o.estimated; r.declaredDate = o.dueDate
            r.paidAmount = o.estimated; r.paidDate = o.dueDate
            l.updateObligationRecord(r)
        }
        return l
    }
}
