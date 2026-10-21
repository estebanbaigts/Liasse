import Foundation

// MARK: - Profil professionnel et fiscal

public enum LegalForm: String, Codable, CaseIterable, Sendable, Identifiable {
    case microEntreprise, eiReel, eurl, sasu, autre
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .microEntreprise: "Micro-entreprise (EI au régime micro)"
        case .eiReel: "Entreprise individuelle au réel"
        case .eurl: "EURL / SARL"
        case .sasu: "SASU / SAS"
        case .autre: "Autre"
        }
    }
    /// Seul le régime micro est calculé automatiquement ; les autres exigent un expert.
    public var isAutomaticallySupported: Bool { self == .microEntreprise }
}

public enum ActivityCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case venteMarchandises, prestationsBIC, liberaleSSI, liberaleCipav
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .venteMarchandises: "Vente de marchandises (BIC)"
        case .prestationsBIC: "Prestations de services commerciales ou artisanales (BIC)"
        case .liberaleSSI: "Activité libérale non réglementée (BNC, SSI)"
        case .liberaleCipav: "Activité libérale réglementée (BNC, Cipav)"
        }
    }
    public var isServices: Bool { self != .venteMarchandises }
}

public enum DeclarationPeriodicity: String, Codable, CaseIterable, Sendable, Identifiable {
    case monthly, quarterly
    public var id: String { rawValue }
    public var label: String { self == .monthly ? "Mensuelle" : "Trimestrielle" }
}

public enum VATRegime: String, Codable, CaseIterable, Sendable, Identifiable {
    case franchise, redevable
    public var id: String { rawValue }
    public var label: String { self == .franchise ? "Franchise en base (TVA non applicable)" : "Redevable de la TVA" }
}

public struct BusinessProfile: Codable, Hashable, Sendable {
    public var ownerName: String = ""
    public var tradeName: String = ""
    public var legalForm: LegalForm = .microEntreprise
    public var activity: ActivityCategory = .liberaleSSI
    public var isArtisan: Bool = false
    public var activityStart: Date = Date()
    public var versementLiberatoire: Bool = false
    public var vatRegime: VATRegime = .franchise
    public var vatDefaultRate: Decimal = Decimal(string: "0.20")!
    public var vatPeriodicity: DeclarationPeriodicity = .monthly
    public var urssafPeriodicity: DeclarationPeriodicity = .quarterly
    /// Taux de prélèvement à la source du foyer (si pas de versement libératoire). Saisi par l'utilisateur.
    public var withholdingTaxRate: Decimal? = nil
    /// Montant de CFE indiqué par l'avis (ou estimation saisie). Nil = inconnu.
    public var cfeAmount: Money? = nil
    public var acre: Bool = false
    /// Taux de cotisations réellement appliqué par l'URSSAF (ACRE, cas particulier). Prioritaire sur le catalogue.
    public var cotisationRateOverride: Decimal? = nil
    // Coordonnées émetteur
    public var address: String = ""
    public var email: String = ""
    public var phone: String = ""
    public var siret: String = ""
    public var vatNumber: String = ""
    public var iban: String = ""
    public var bic: String = ""
    // Conditions de facturation
    public var paymentTermDays: Int = 30
    public var latePenaltyText: String = "Pénalités de retard : trois fois le taux d'intérêt légal. Indemnité forfaitaire pour frais de recouvrement : 40 €."
    public var invoiceFooter: String = ""
    // Pilotage
    public var monthlyRevenueGoal: Money = Money(euros: 6000)
    public var defaultDailyRate: Money = Money(euros: 500)
    public var openingBalance: Money = .zero
    public var openingBalanceDate: Date = Date()
    public var onboardingCompleted: Bool = false

    public init() {}

    public var displayName: String { tradeName.isEmpty ? ownerName : tradeName }

    /// Mentions légales obligatoires calculées à partir de la situation réelle.
    public var legalMentions: [String] {
        var m: [String] = []
        if legalForm == .microEntreprise || legalForm == .eiReel {
            m.append("Entrepreneur individuel (EI)")
        }
        if vatRegime == .franchise { m.append("TVA non applicable, art. 293 B du CGI") }
        return m
    }
}

// MARK: - Clients et missions

public struct Client: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var isCompany: Bool = true
    public var contactName: String = ""
    public var address: String = ""
    public var email: String = ""
    public var siren: String = ""
    public var vatNumber: String = ""
    public var notes: String = ""
    public var createdAt = Date()
    public init(name: String) { self.name = name }
}

public enum MissionStatus: String, Codable, CaseIterable, Sendable, Identifiable {
    case planned, active, done
    public var id: String { rawValue }
    public var label: String { switch self { case .planned: "Prévue"; case .active: "En cours"; case .done: "Terminée" } }
}

public struct Mission: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var clientId: UUID?
    public var title: String
    public var status: MissionStatus = .active
    public var dailyRate: Money
    public var plannedDays: Decimal = 0
    public var workedDays: Decimal = 0
    public var startDate = Date()
    public var endDate: Date?
    /// Frais ou commissions (plateforme, portage…) déduits de la rentabilité économique.
    public var fees: Money = .zero
    public init(title: String, clientId: UUID?, dailyRate: Money) {
        self.title = title; self.clientId = clientId; self.dailyRate = dailyRate
    }
    public var plannedAmount: Money { dailyRate.times(plannedDays) }
}

// MARK: - Documents commerciaux

public enum LineUnit: String, Codable, CaseIterable, Sendable, Identifiable {
    case day, hour, unit, flat
    public var id: String { rawValue }
    public var label: String { switch self { case .day: "jour"; case .hour: "heure"; case .unit: "unité"; case .flat: "forfait" } }
}

public struct DocumentLine: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var label: String
    public var quantity: Decimal
    public var unit: LineUnit
    public var unitPrice: Money
    public var vatRate: Decimal
    public init(label: String, quantity: Decimal, unit: LineUnit, unitPrice: Money, vatRate: Decimal = 0) {
        self.label = label; self.quantity = quantity; self.unit = unit; self.unitPrice = unitPrice; self.vatRate = vatRate
    }
    public var totalHT: Money { unitPrice.times(quantity) }
}

public struct DocumentTotals: Hashable, Sendable {
    public var grossHT: Money
    public var discount: Money
    public var netHT: Money
    public var vatByRate: [(rate: Decimal, amount: Money)]
    public var vat: Money
    public var ttc: Money
    public static func == (l: Self, r: Self) -> Bool { l.netHT == r.netHT && l.vat == r.vat && l.ttc == r.ttc && l.discount == r.discount }
    public func hash(into h: inout Hasher) { h.combine(netHT); h.combine(vat); h.combine(ttc) }

    /// La remise globale est répartie au prorata de chaque taux de TVA.
    public static func compute(lines: [DocumentLine], discount: Money, vatApplicable: Bool) -> DocumentTotals {
        let gross = lines.sum(\.totalHT)
        let d = min(max(discount, .zero), gross.clamped(min: .zero))
        var groups: [Decimal: Money] = [:]
        for l in lines { groups[vatApplicable ? l.vatRate : 0, default: .zero] += l.totalHT }
        var vatLines: [(Decimal, Money)] = []
        var vatTotal = Money.zero
        for (rate, base) in groups.sorted(by: { $0.key < $1.key }) where rate > 0 {
            let share = gross.isZero ? Money.zero : Money(decimalEuros: d.decimal * base.decimal / gross.decimal)
            let amount = (base - share).applying(rate: rate)
            vatLines.append((rate, amount)); vatTotal += amount
        }
        let net = gross - d
        return DocumentTotals(grossHT: gross, discount: d, netHT: net, vatByRate: vatLines, vat: vatTotal, ttc: net + vatTotal)
    }
}

public struct PartySnapshot: Codable, Hashable, Sendable {
    public var name: String
    public var address: String
    public var email: String
    public var siret: String
    public var vatNumber: String
    public init(name: String, address: String, email: String, siret: String, vatNumber: String) {
        self.name = name; self.address = address; self.email = email; self.siret = siret; self.vatNumber = vatNumber
    }
    public static func of(client: Client) -> PartySnapshot {
        PartySnapshot(name: client.name, address: client.address, email: client.email, siret: client.siren, vatNumber: client.vatNumber)
    }
    public static func of(profile: BusinessProfile) -> PartySnapshot {
        PartySnapshot(name: profile.displayName, address: profile.address, email: profile.email, siret: profile.siret, vatNumber: profile.vatNumber)
    }
}

public struct HistoryEntry: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var date: Date
    public var action: String
    public init(date: Date = Date(), action: String) { self.date = date; self.action = action }
}

public enum PaymentMethod: String, Codable, CaseIterable, Sendable, Identifiable {
    case transfer, card, check, cash, other
    public var id: String { rawValue }
    public var label: String { switch self { case .transfer: "Virement"; case .card: "Carte"; case .check: "Chèque"; case .cash: "Espèces"; case .other: "Autre" } }
}

public struct Payment: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var date: Date
    public var amount: Money
    public var method: PaymentMethod = .transfer
    public var note: String = ""
    public var transactionId: UUID?
    public init(date: Date, amount: Money, method: PaymentMethod = .transfer) {
        self.date = date; self.amount = amount; self.method = method
    }
}

public enum InvoiceKind: String, Codable, Sendable { case invoice, creditNote }

/// État persistant (ce que l'utilisateur a décidé). Le statut affiché est dérivé.
public enum InvoiceLifecycle: String, Codable, Sendable { case draft, issued, cancelled }

public enum InvoiceStatus: String, CaseIterable, Sendable, Identifiable {
    case draft, issued, partiallyPaid, paid, overdue, cancelled
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .draft: "Brouillon"; case .issued: "Émise"; case .partiallyPaid: "Partiellement payée"
        case .paid: "Payée"; case .overdue: "En retard"; case .cancelled: "Annulée"
        }
    }
}

public struct Invoice: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var kind: InvoiceKind = .invoice
    public var lifecycle: InvoiceLifecycle = .draft
    /// Attribué uniquement à l'émission ; jamais réutilisé.
    public var number: String?
    public var clientId: UUID?
    public var missionId: UUID?
    public var quoteId: UUID?
    /// Pour un avoir : facture d'origine.
    public var correctsInvoiceId: UUID?
    public var issueDate: Date
    public var dueDate: Date
    public var serviceDate: Date?
    public var lines: [DocumentLine] = []
    public var discount: Money = .zero
    public var paymentTerms: String = ""
    public var notes: String = ""
    public var payments: [Payment] = []
    public var history: [HistoryEntry] = []
    /// Figés à l'émission pour que le document reste identique même si le client change.
    public var clientSnapshot: PartySnapshot?
    public var issuerSnapshot: PartySnapshot?
    public var vatApplicable: Bool = false
    public var legalMentions: [String] = []
    public var lastReminderDate: Date?

    public init(clientId: UUID?, issueDate: Date, dueDate: Date) {
        self.clientId = clientId; self.issueDate = issueDate; self.dueDate = dueDate
    }

    public var totals: DocumentTotals { DocumentTotals.compute(lines: lines, discount: discount, vatApplicable: vatApplicable) }
    /// Montant signé (négatif pour un avoir).
    public var signedTTC: Money { kind == .creditNote ? -totals.ttc : totals.ttc }
    public var paidAmount: Money { payments.sum(\.amount) }
    public var balance: Money { (totals.ttc - paidAmount).clamped(min: .zero) }
    public var isCountable: Bool { lifecycle == .issued }

    public func status(on date: Date, calendar: Calendar = .fr) -> InvoiceStatus {
        switch lifecycle {
        case .draft: return .draft
        case .cancelled: return .cancelled
        case .issued:
            if kind == .creditNote { return .issued }
            if balance.isZero && !totals.ttc.isZero { return .paid }
            if calendar.startOfDay(for: date) > calendar.startOfDay(for: dueDate) { return .overdue }
            return paidAmount.isPositive ? .partiallyPaid : .issued
        }
    }

    public func daysLate(on date: Date, calendar: Calendar = .fr) -> Int {
        max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: dueDate), to: calendar.startOfDay(for: date)).day ?? 0)
    }
}

public enum QuoteStatus: String, Codable, CaseIterable, Sendable, Identifiable {
    case draft, sent, accepted, refused, invoiced
    public var id: String { rawValue }
    public var label: String {
        switch self { case .draft: "Brouillon"; case .sent: "Envoyé"; case .accepted: "Accepté"; case .refused: "Refusé"; case .invoiced: "Facturé" }
    }
}

public struct Quote: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var number: String?
    public var status: QuoteStatus = .draft
    public var clientId: UUID?
    public var missionId: UUID?
    public var issueDate: Date
    public var validUntil: Date
    public var lines: [DocumentLine] = []
    public var discount: Money = .zero
    public var notes: String = ""
    public var vatApplicable: Bool = false
    public var invoiceId: UUID?
    public var history: [HistoryEntry] = []
    public var clientSnapshot: PartySnapshot?
    public var issuerSnapshot: PartySnapshot?
    public var legalMentions: [String] = []
    public init(clientId: UUID?, issueDate: Date, validUntil: Date) {
        self.clientId = clientId; self.issueDate = issueDate; self.validUntil = validUntil
    }
    public var totals: DocumentTotals { DocumentTotals.compute(lines: lines, discount: discount, vatApplicable: vatApplicable) }
}

// MARK: - Dépenses et transactions

public enum ExpenseCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case software, hardware, office, travel, meals, training, insurance, bank, telecom, fees, subcontracting, taxes, other, unclassified
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .software: "Logiciels & abonnements"; case .hardware: "Matériel"; case .office: "Bureau & fournitures"
        case .travel: "Déplacements"; case .meals: "Repas"; case .training: "Formation"; case .insurance: "Assurances"
        case .bank: "Frais bancaires"; case .telecom: "Téléphone & internet"; case .fees: "Honoraires"
        case .subcontracting: "Sous-traitance"; case .taxes: "Impôts & cotisations"; case .other: "Autre"; case .unclassified: "À classer"
        }
    }
}

public enum Recurrence: String, Codable, CaseIterable, Sendable, Identifiable {
    case none, monthly, yearly
    public var id: String { rawValue }
    public var label: String { switch self { case .none: "Ponctuelle"; case .monthly: "Mensuelle"; case .yearly: "Annuelle" } }
}

public enum ExpenseStatus: String, Codable, CaseIterable, Sendable, Identifiable {
    case planned, paid
    public var id: String { rawValue }
    public var label: String { self == .paid ? "Payée" : "Prévue" }
}

public struct Expense: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var date: Date
    public var amount: Money
    public var vatAmount: Money = .zero
    public var category: ExpenseCategory
    public var supplier: String = ""
    public var label: String = ""
    public var missionId: UUID?
    public var status: ExpenseStatus
    public var recurrence: Recurrence = .none
    public var recurrenceEnd: Date?
    /// Nom de fichier dans le dossier des justificatifs (stockage local).
    public var attachment: String?
    public var transactionId: UUID?
    public var createdAt = Date()
    public init(date: Date, amount: Money, category: ExpenseCategory, status: ExpenseStatus) {
        self.date = date; self.amount = amount; self.category = category; self.status = status
    }
}

public struct BankTransaction: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var date: Date
    public var label: String
    public var amount: Money
    /// Empreinte stable (date + montant + libellé normalisé + rang) pour éviter les doublons.
    public var fingerprint: String
    public var importedAt = Date()
    public var linkedExpenseId: UUID?
    public var linkedInvoiceId: UUID?
    public var ignored = false
    public init(date: Date, label: String, amount: Money, fingerprint: String) {
        self.date = date; self.label = label; self.amount = amount; self.fingerprint = fingerprint
    }
    public var isLinked: Bool { linkedExpenseId != nil || linkedInvoiceId != nil || ignored }
}

// MARK: - Obligations

public enum ObligationKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case cotisations, cfp, versementLiberatoire, incomeTax, vat, cfe
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .cotisations: "Cotisations sociales URSSAF"
        case .cfp: "Formation professionnelle (CFP)"
        case .versementLiberatoire: "Versement libératoire de l'impôt"
        case .incomeTax: "Impôt sur le revenu (estimation)"
        case .vat: "TVA à reverser"
        case .cfe: "Cotisation foncière des entreprises (CFE)"
        }
    }
    public var shortLabel: String {
        switch self {
        case .cotisations: "URSSAF"; case .cfp: "CFP"; case .versementLiberatoire: "Versement libératoire"
        case .incomeTax: "Impôt sur le revenu"; case .vat: "TVA"; case .cfe: "CFE"
        }
    }
}

public enum ObligationStatus: String, CaseIterable, Sendable, Identifiable {
    case provisional, toDeclare, declared, toPay, paid, toVerify
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .provisional: "Prévisionnelle"; case .toDeclare: "À déclarer"; case .declared: "Déclarée"
        case .toPay: "À payer"; case .paid: "Payée"; case .toVerify: "À vérifier"
        }
    }
}

/// Ce que l'utilisateur a réellement déclaré / payé pour une obligation donnée.
public struct ObligationRecord: Codable, Hashable, Identifiable, Sendable {
    public var id: String { key }
    public var key: String
    public var declaredAmount: Money?
    public var declaredDate: Date?
    public var paidAmount: Money?
    public var paidDate: Date?
    public var note: String = ""
    public init(key: String) { self.key = key }
}

// MARK: - Calendrier français

extension Calendar {
    public static let fr: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "fr_FR")
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        c.firstWeekday = 2
        return c
    }()

    public func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    public func startOfMonth(_ d: Date) -> Date { date(from: dateComponents([.year, .month], from: d))! }
    public func endOfMonth(_ d: Date) -> Date { date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth(d))! }
}
