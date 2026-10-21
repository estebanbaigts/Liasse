import Foundation

/// Intervalle de dates inclusif, à la journée.
public struct Period: Hashable, Codable, Sendable {
    public var start: Date
    public var end: Date
    public init(start: Date, end: Date) { self.start = start; self.end = end }

    public func contains(_ d: Date, calendar: Calendar = .fr) -> Bool {
        let day = calendar.startOfDay(for: d)
        return day >= calendar.startOfDay(for: start) && day <= calendar.startOfDay(for: end)
    }

    public static func month(of d: Date, calendar: Calendar = .fr) -> Period {
        Period(start: calendar.startOfMonth(d), end: calendar.endOfMonth(d))
    }
    public static func quarter(of d: Date, calendar: Calendar = .fr) -> Period {
        let m = calendar.component(.month, from: d), y = calendar.component(.year, from: d)
        let qStart = ((m - 1) / 3) * 3 + 1
        let s = calendar.date(y, qStart, 1)
        return Period(start: calendar.startOfMonth(s), end: calendar.endOfMonth(calendar.date(y, qStart + 2, 1)))
    }
    public static func year(of d: Date, calendar: Calendar = .fr) -> Period {
        let y = calendar.component(.year, from: d)
        return Period(start: calendar.startOfDay(for: calendar.date(y, 1, 1)), end: calendar.date(y, 12, 31))
    }
    public func previous(calendar: Calendar = .fr) -> Period {
        let months = (calendar.dateComponents([.month], from: calendar.startOfMonth(start), to: calendar.startOfMonth(end)).month ?? 0) + 1
        let s = calendar.date(byAdding: .month, value: -months, to: calendar.startOfMonth(start))!
        let e = calendar.date(byAdding: .day, value: -1, to: calendar.startOfMonth(start))!
        return Period(start: s, end: e)
    }
}

/// Une échéance calculée : estimation, et ce que l'utilisateur a réellement déclaré / payé.
public struct Obligation: Identifiable, Hashable, Sendable {
    public var id: String { key }
    public var key: String
    public var kind: ObligationKind
    public var period: Period
    public var dueDate: Date
    public var base: Money?
    public var rate: Decimal?
    public var estimated: Money?
    public var record: ObligationRecord?
    public var rule: TaxRule?
    public var status: ObligationStatus
    /// Explication en langage clair du calcul (affichée dans le détail).
    public var explanation: String
    public var warnings: [String]
    public var requiresDeclaration: Bool

    /// Montant de référence pour la réserve : déclaré si connu, sinon estimé.
    public var expected: Money? { record?.declaredAmount ?? estimated }
    public var paid: Money { record?.paidAmount ?? .zero }
    public var remaining: Money { status == .paid ? .zero : ((expected ?? .zero) - paid).clamped(min: .zero) }
    /// Écart entre déclaré et estimé (prévision vs réalité).
    public var variance: Money? {
        guard let d = record?.declaredAmount, let e = estimated else { return nil }
        return d - e
    }
}

public struct ReserveSplit: Hashable, Sendable {
    public var collectedHT: Money
    public var cotisations: Money
    public var cfp: Money
    public var incomeTax: Money
    public var vat: Money
    public var total: Money { cotisations + cfp + incomeTax + vat }
    public var free: Money { collectedHT + vat - total }
    public var assumptions: [String]
}

public struct TaxEngine: Sendable {
    public let ledger: Ledger
    public let calendar: Calendar
    public init(ledger: Ledger, calendar: Calendar = .fr) { self.ledger = ledger; self.calendar = calendar }

    var profile: BusinessProfile { ledger.profile }

    // MARK: Bases

    /// Part HT d'un paiement (en franchise, HT = TTC). Prorata HT/TTC de la facture sinon.
    public func htPart(of payment: Payment, in invoice: Invoice) -> Money {
        let t = invoice.totals
        guard invoice.vatApplicable, t.ttc.isPositive, t.vat.isPositive else { return payment.amount }
        return Money(decimalEuros: payment.amount.decimal * t.netHT.decimal / t.ttc.decimal)
    }

    public func collectedPayments(in period: Period) -> [(invoice: Invoice, payment: Payment)] {
        ledger.invoices.filter { $0.kind == .invoice && $0.lifecycle != .draft }
            .flatMap { inv in inv.payments.filter { period.contains($0.date, calendar: calendar) }.map { (inv, $0) } }
    }

    /// CA encaissé HT : la base légale des cotisations en micro (jamais le facturé, jamais diminué des dépenses).
    public func collectedHT(in period: Period) -> Money {
        collectedPayments(in: period).sum { htPart(of: $0.payment, in: $0.invoice) }
    }

    public func vatCollected(in period: Period) -> Money {
        collectedPayments(in: period).sum { $0.payment.amount - htPart(of: $0.payment, in: $0.invoice) }
    }

    public func vatDeductible(in period: Period) -> Money {
        ledger.expenses.filter { $0.status == .paid && period.contains($0.date, calendar: calendar) }.sum(\.vatAmount)
    }

    func rule(_ key: RuleKey, on date: Date) -> TaxRule? {
        ledger.rules.rule(key, activity: profile.activity, artisan: profile.isArtisan, on: date)
    }

    public func cotisationRate(on date: Date) -> (rate: Decimal, rule: TaxRule?)? {
        if let o = profile.cotisationRateOverride { return (o, nil) }
        return rule(.cotisations, on: date).map { ($0.value, $0) }
    }

    // MARK: Échéances

    public func declarationPeriods(year: Int, periodicity: DeclarationPeriodicity) -> [Period] {
        let months = periodicity == .monthly ? Array(1...12) : [1, 4, 7, 10]
        return months.map { m in
            let s = calendar.date(year, m, 1)
            return periodicity == .monthly ? Period.month(of: s, calendar: calendar) : Period.quarter(of: s, calendar: calendar)
        }
    }

    /// Fiche F23257 : dernier jour du mois suivant la période (mensuel et trimestriel), reporté au jour ouvré.
    public func urssafDueDate(for p: Period) -> Date {
        let next = calendar.date(byAdding: .month, value: 1, to: calendar.startOfMonth(p.end))!
        return FrenchCalendar.nextBusinessDay(onOrAfter: calendar.endOfMonth(next), calendar: calendar)
    }

    func status(for period: Period, due: Date, record: ObligationRecord?, today: Date, needsDeclaration: Bool, unknown: Bool) -> ObligationStatus {
        if let r = record, let paid = r.paidAmount, paid.isPositive || r.paidDate != nil {
            let target = r.declaredAmount ?? paid
            if paid >= target { return .paid }
        }
        if unknown { return .toVerify }
        if record?.declaredAmount != nil { return .toPay }
        if calendar.startOfDay(for: today) <= calendar.startOfDay(for: period.end) { return .provisional }
        return needsDeclaration ? .toDeclare : .toPay
    }

    func key(_ kind: ObligationKind, _ p: Period) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.calendar = calendar; f.timeZone = calendar.timeZone
        return "\(kind.rawValue)|\(f.string(from: p.start))|\(f.string(from: p.end))"
    }

    func record(_ key: String) -> ObligationRecord? { ledger.obligationRecords.first { $0.key == key } }

    public func periodLabel(_ p: Period, periodicity: DeclarationPeriodicity) -> String {
        let y = calendar.component(.year, from: p.start)
        if periodicity == .quarterly {
            return "T\((calendar.component(.month, from: p.start) - 1) / 3 + 1) \(y)"
        }
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "LLLL yyyy"
        return f.string(from: p.start).capitalized(with: Locale(identifier: "fr_FR"))
    }

    /// Libellé court d'une obligation : période déclarative, ou année pour les obligations annuelles.
    public func label(_ o: Obligation) -> String {
        switch o.kind {
        case .cfe, .incomeTax: return "\(o.kind.shortLabel) · \(calendar.component(.year, from: o.period.start))"
        case .vat: return "\(o.kind.shortLabel) · \(periodLabel(o.period, periodicity: profile.vatPeriodicity))"
        default: return "\(o.kind.shortLabel) · \(periodLabel(o.period, periodicity: profile.urssafPeriodicity))"
        }
    }

    /// Toutes les obligations de l'année, dans l'ordre des échéances.
    public func obligations(year: Int, today: Date) -> [Obligation] {
        guard profile.legalForm.isAutomaticallySupported else { return [] }
        var out: [Obligation] = []
        let startYear = calendar.component(.year, from: profile.activityStart)
        guard year >= startYear else { return [] }
        let activityStartDay = calendar.startOfDay(for: profile.activityStart)

        for p in declarationPeriods(year: year, periodicity: profile.urssafPeriodicity) where p.end >= activityStartDay {
            let due = urssafDueDate(for: p)
            let base = collectedHT(in: p)
            let label = periodLabel(p, periodicity: profile.urssafPeriodicity)

            // Cotisations sociales
            let k = key(.cotisations, p), rec = record(k)
            if let r = cotisationRate(on: p.start) {
                var warnings: [String] = []
                if r.rule == nil { warnings.append("Taux personnalisé saisi dans tes réglages.") }
                if profile.acre && profile.cotisationRateOverride == nil {
                    warnings.append("ACRE déclarée : la réduction n'est pas calculée automatiquement. Saisis le taux indiqué par l'URSSAF dans les réglages.")
                }
                if let n = r.rule?.note, !n.isEmpty { warnings.append(n) }
                out.append(Obligation(key: k, kind: .cotisations, period: p, dueDate: due, base: base, rate: r.rate,
                                      estimated: base.applying(rate: r.rate), record: rec, rule: r.rule,
                                      status: status(for: p, due: due, record: rec, today: today, needsDeclaration: true, unknown: false),
                                      explanation: "\(label) : \(base) encaissés × \(MoneyFormat.percent(r.rate, digits: 2)). Déclaration et paiement avant le \(due.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "fr_FR")))).",
                                      warnings: warnings, requiresDeclaration: true))
            } else if base.isZero {
                // Aucun encaissement : 0 € quel que soit le taux (la déclaration à zéro reste obligatoire).
                out.append(Obligation(key: k, kind: .cotisations, period: p, dueDate: due, base: base, rate: nil, estimated: .zero,
                                      record: rec, rule: nil,
                                      status: status(for: p, due: due, record: rec, today: today, needsDeclaration: true, unknown: false),
                                      explanation: "\(label) : aucun encaissement, déclaration à 0 €.", warnings: [], requiresDeclaration: true))
            } else {
                out.append(Obligation(key: k, kind: .cotisations, period: p, dueDate: due, base: base, rate: nil, estimated: nil,
                                      record: rec, rule: nil,
                                      status: status(for: p, due: due, record: rec, today: today, needsDeclaration: true, unknown: true),
                                      explanation: "\(label) : aucun taux vérifié pour cette période dans le catalogue.",
                                      warnings: ["Ajoute le taux applicable dans Réglages › Règles fiscales, ou saisis le montant déclaré."], requiresDeclaration: true))
            }

            // CFP
            let kc = key(.cfp, p), rc = record(kc)
            if let rule = rule(.cfp, on: p.start) {
                out.append(Obligation(key: kc, kind: .cfp, period: p, dueDate: due, base: base, rate: rule.value,
                                      estimated: base.applying(rate: rule.value), record: rc, rule: rule,
                                      status: status(for: p, due: due, record: rc, today: today, needsDeclaration: true, unknown: false),
                                      explanation: "\(label) : \(base) × \(MoneyFormat.percent(rule.value, digits: 2)).",
                                      warnings: rule.confidence == .toVerify ? [rule.note] : [], requiresDeclaration: true))
            }

            // Versement libératoire
            if profile.versementLiberatoire {
                let kv = key(.versementLiberatoire, p), rv = record(kv)
                let r = rule(.versementLiberatoire, on: p.start)
                out.append(Obligation(key: kv, kind: .versementLiberatoire, period: p, dueDate: due, base: base, rate: r?.value,
                                      estimated: r.map { base.applying(rate: $0.value) }, record: rv, rule: r,
                                      status: status(for: p, due: due, record: rv, today: today, needsDeclaration: true, unknown: r == nil),
                                      explanation: r.map { "\(label) : \(base) × \(MoneyFormat.percent($0.value, digits: 2)), payé avec les cotisations." } ?? "Taux du versement libératoire non disponible pour cette période.",
                                      warnings: ["Option possible seulement si ton revenu fiscal de référence N-2 respecte le plafond."], requiresDeclaration: true))
            }
        }

        // TVA
        if profile.vatRegime == .redevable {
            for p in declarationPeriods(year: year, periodicity: profile.vatPeriodicity) where p.end >= activityStartDay {
                let collected = vatCollected(in: p), deductible = vatDeductible(in: p)
                let net = (collected - deductible)
                let due = FrenchCalendar.nextBusinessDay(onOrAfter: calendar.date(byAdding: DateComponents(month: 1, day: 18), to: calendar.startOfMonth(p.end))!, calendar: calendar)
                let k = key(.vat, p), rec = record(k)
                out.append(Obligation(key: k, kind: .vat, period: p, dueDate: due, base: collected, rate: nil,
                                      estimated: net.clamped(min: .zero), record: rec, rule: nil,
                                      status: status(for: p, due: due, record: rec, today: today, needsDeclaration: true, unknown: false),
                                      explanation: "TVA collectée sur encaissements \(collected) − TVA déductible sur dépenses payées \(deductible)" + (net.isNegative ? " : crédit de TVA de \(-net)." : "."),
                                      warnings: ["La date limite de dépôt dépend de ton SIE et de ton numéro SIREN : vérifie-la sur ton espace professionnel impots.gouv.fr. TVA sur prestations exigible à l'encaissement (hors option sur les débits)."],
                                      requiresDeclaration: true))
            }
        }

        // Impôt sur le revenu (hors versement libératoire) — réserve indicative
        if !profile.versementLiberatoire {
            let p = Period.year(of: calendar.date(year, 6, 1), calendar: calendar)
            let ca = collectedHT(in: p)
            let k = key(.incomeTax, p), rec = record(k)
            let ab = rule(.abattement, on: p.start)
            var warnings = ["Estimation : l'impôt dépend de tout ton foyer fiscal. Il est payé par les acomptes du prélèvement à la source et le solde après ta déclaration de revenus."]
            var estimated: Money? = nil
            var explanation = "Abattement ou taux de prélèvement manquant."
            if ca.isZero {
                estimated = .zero
                explanation = "Aucun encaissement sur l'année : pas d'impôt lié à l'activité."
            } else if let ab, let rate = profile.withholdingTaxRate {
                let allowance = max(ca.applying(rate: ab.value), ca.isPositive ? Money(euros: 305) : .zero)
                let taxable = (ca - allowance).clamped(min: .zero)
                estimated = taxable.applying(rate: rate)
                explanation = "\(ca) encaissés − abattement \(MoneyFormat.percent(ab.value, digits: 0)) = \(taxable) imposables × ton taux de prélèvement \(MoneyFormat.percent(rate, digits: 1))."
            } else if profile.withholdingTaxRate == nil {
                warnings.append("Saisis ton taux de prélèvement à la source (impots.gouv.fr › Gérer mon prélèvement) pour obtenir une estimation.")
            }
            let due = calendar.date(year + 1, 9, 25)
            out.append(Obligation(key: k, kind: .incomeTax, period: p, dueDate: due, base: ca, rate: profile.withholdingTaxRate,
                                  estimated: estimated, record: rec, rule: ab,
                                  status: status(for: p, due: due, record: rec, today: today, needsDeclaration: true, unknown: estimated == nil),
                                  explanation: explanation, warnings: warnings, requiresDeclaration: true))
        }

        // CFE : exonérée l'année de création, due au 15 décembre.
        if year > startYear {
            let p = Period.year(of: calendar.date(year, 6, 1), calendar: calendar)
            let due = FrenchCalendar.nextBusinessDay(onOrAfter: calendar.date(year, 12, 15), calendar: calendar)
            let k = key(.cfe, p), rec = record(k)
            out.append(Obligation(key: k, kind: .cfe, period: p, dueDate: due, base: nil, rate: nil,
                                  estimated: profile.cfeAmount, record: rec, rule: nil,
                                  status: status(for: p, due: due, record: rec, today: today, needsDeclaration: false, unknown: profile.cfeAmount == nil),
                                  explanation: profile.cfeAmount.map { "Montant saisi d'après ton avis de CFE : \($0)." } ?? "Montant inconnu : il figure sur ton avis, disponible sur ton espace professionnel impots.gouv.fr.",
                                  warnings: ["La CFE dépend de ta commune : seul l'avis d'imposition fait foi."], requiresDeclaration: false))
        }
        return out.sorted { $0.dueDate < $1.dueDate }
    }

    /// Répartition indicative d'un encaissement : ce qu'il serait prudent de réserver.
    public func split(payment: Payment, invoice: Invoice) -> ReserveSplit {
        let ht = htPart(of: payment, in: invoice)
        let vat = payment.amount - ht
        return split(collectedHT: ht, vat: vat, on: payment.date)
    }

    public func split(collectedHT ht: Money, vat: Money, on date: Date) -> ReserveSplit {
        var assumptions: [String] = []
        let cot: Money
        if let r = cotisationRate(on: date) {
            cot = ht.applying(rate: r.rate)
            assumptions.append("Cotisations : \(MoneyFormat.percent(r.rate, digits: 2)) du CA encaissé" + (r.rule == nil ? " (taux personnalisé)." : " (\(r.rule!.sourceName))."))
        } else { cot = .zero; assumptions.append("Aucun taux de cotisations vérifié pour cette date.") }
        let cfp = rule(.cfp, on: date).map { ht.applying(rate: $0.value) } ?? .zero
        var tax = Money.zero
        if profile.versementLiberatoire {
            if let r = rule(.versementLiberatoire, on: date) { tax = ht.applying(rate: r.value); assumptions.append("Versement libératoire : \(MoneyFormat.percent(r.value, digits: 1)).") }
        } else if let rate = profile.withholdingTaxRate, let ab = rule(.abattement, on: date) {
            tax = ht.applying(rate: (1 - ab.value) * rate)
            assumptions.append("Impôt : \(MoneyFormat.percent(rate, digits: 1)) sur \(MoneyFormat.percent(1 - ab.value, digits: 0)) du CA (après abattement).")
        } else {
            assumptions.append("Impôt sur le revenu non estimé : taux de prélèvement non renseigné.")
        }
        if vat.isPositive { assumptions.append("TVA collectée mise de côté intégralement (la TVA déductible sera imputée à la déclaration).") }
        return ReserveSplit(collectedHT: ht, cotisations: cot, cfp: cfp, incomeTax: tax, vat: vat, assumptions: assumptions)
    }

    /// Contrôle des seuils : franchise de TVA et plafond micro.
    public func thresholdAlerts(year: Int, today: Date) -> [String] {
        let p = Period.year(of: calendar.date(year, 6, 1), calendar: calendar)
        let ca = collectedHT(in: p)
        var out: [String] = []
        if profile.vatRegime == .franchise {
            if let maj = rule(.vatThresholdMajore, on: today), ca.decimal > maj.value {
                out.append("Ton CA \(year) (\(ca)) dépasse le seuil majoré de franchise de TVA (\(maj.formattedValue)) : la TVA est due dès le jour du dépassement.")
            } else if let base = rule(.vatThresholdBase, on: today), ca.decimal > base.value {
                out.append("Ton CA \(year) (\(ca)) dépasse le seuil de base de franchise de TVA (\(base.formattedValue)) : la TVA s'appliquera au 1er janvier suivant si le seuil majoré n'est pas atteint.")
            } else if let base = rule(.vatThresholdBase, on: today), ca.decimal > base.value * Decimal(string: "0.85")! {
                out.append("Ton CA \(year) (\(ca)) approche du seuil de franchise de TVA (\(base.formattedValue)).")
            }
        }
        if let cap = rule(.microThreshold, on: today), ca.decimal > cap.value * Decimal(string: "0.85")! {
            out.append("Ton CA \(year) (\(ca)) approche ou dépasse le plafond du régime micro (\(cap.formattedValue)). Parles-en à un expert-comptable.")
        }
        return out
    }
}
