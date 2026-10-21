import Foundation

/// Fiabilité d'une règle : vérifiée sur une source officielle, ou à confirmer.
public enum RuleConfidence: String, Codable, Sendable, CaseIterable {
    case verified, toVerify
    public var label: String { self == .verified ? "Vérifiée" : "À vérifier" }
}

public enum RuleKey: String, Codable, Sendable, CaseIterable {
    case cotisations, cfp, versementLiberatoire, abattement, microThreshold, vatThresholdBase, vatThresholdMajore, vlIncomeLimitSingle
    public var label: String {
        switch self {
        case .cotisations: "Taux de cotisations sociales"
        case .cfp: "Contribution à la formation professionnelle"
        case .versementLiberatoire: "Versement libératoire"
        case .abattement: "Abattement forfaitaire micro-fiscal"
        case .microThreshold: "Plafond de CA du régime micro"
        case .vatThresholdBase: "Seuil de franchise TVA (base)"
        case .vatThresholdMajore: "Seuil de franchise TVA (majoré)"
        case .vlIncomeLimitSingle: "Plafond RFR N-2 pour le versement libératoire (personne seule)"
        }
    }
}

public enum RuleNature: String, Codable, Sendable {
    case rateOnCollectedRevenue, rateOnAnnualRevenue, threshold, allowance
    public var label: String {
        switch self {
        case .rateOnCollectedRevenue: "Taux appliqué au CA encaissé de la période"
        case .rateOnAnnualRevenue: "Taux appliqué au CA annuel"
        case .threshold: "Seuil en euros"
        case .allowance: "Abattement appliqué au CA"
        }
    }
}

/// Une règle fiscale ou sociale documentée. Toutes les valeurs du moteur viennent de ce catalogue.
public struct TaxRule: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var key: RuleKey
    /// Catégories concernées ; vide = toutes.
    public var activities: [ActivityCategory]
    /// Restriction artisan (CFP) : nil = sans objet.
    public var artisan: Bool?
    public var regime: String
    public var nature: RuleNature
    public var base: String
    /// Taux (0.256) ou montant en euros pour un seuil.
    public var value: Decimal
    public var effectiveFrom: Date
    public var effectiveTo: Date?
    public var sourceName: String
    public var sourceURL: String
    public var verifiedOn: Date
    public var confidence: RuleConfidence
    public var note: String
    public var userModified: Bool = false

    /// Comparaison à la journée (fuseau Europe/Paris) : une règle effective le 1er janvier couvre toute cette journée.
    public func applies(activity: ActivityCategory, artisan isArtisan: Bool, on date: Date, calendar: Calendar = .fr) -> Bool {
        let day = calendar.startOfDay(for: date)
        return (activities.isEmpty || activities.contains(activity))
            && (artisan == nil || artisan == isArtisan)
            && calendar.startOfDay(for: effectiveFrom) <= day
            && (effectiveTo.map { day <= calendar.startOfDay(for: $0) } ?? true)
    }

    public var formattedValue: String {
        nature == .threshold ? MoneyFormat.string(Money(decimalEuros: value), showCents: false) : MoneyFormat.percent(value, digits: 2)
    }
}

public struct TaxRuleSet: Codable, Hashable, Sendable {
    public var version: Int
    public var rules: [TaxRule]

    /// Règle applicable la plus récente pour une date donnée, ou nil si aucune règle vérifiée ne couvre cette date.
    public func rule(_ key: RuleKey, activity: ActivityCategory, artisan: Bool, on date: Date) -> TaxRule? {
        rules.filter { $0.key == key && $0.applies(activity: activity, artisan: artisan, on: date) }
            .max { $0.effectiveFrom < $1.effectiveFrom }
    }
}

extension TaxRuleSet {
    /// Catalogue par défaut — régime micro-entrepreneur, vérifié le 21/10/2026.
    /// Sources : entreprendre.service-public.gouv.fr (fiches F36232, F23267, F23459, F21746, F23257).
    public static let defaultCatalogue: TaxRuleSet = {
        let cal = Calendar.fr
        let from2026 = cal.date(2026, 1, 1)
        let checked = cal.date(2026, 10, 21)
        let f36232 = "https://entreprendre.service-public.gouv.fr/vosdroits/F36232"
        let f23267 = "https://entreprendre.service-public.gouv.fr/vosdroits/F23267"
        let f23459 = "https://entreprendre.service-public.gouv.fr/vosdroits/F23459"
        let f21746 = "https://entreprendre.service-public.gouv.fr/vosdroits/F21746"
        let sp = "Service-public.gouv.fr (Entreprendre)"
        func d(_ s: String) -> Decimal { Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))! }
        func r(_ id: String, _ key: RuleKey, _ acts: [ActivityCategory], artisan: Bool? = nil, _ nature: RuleNature,
               _ base: String, _ value: String, _ url: String, _ conf: RuleConfidence = .verified, _ note: String = "") -> TaxRule {
            TaxRule(id: id, key: key, activities: acts, artisan: artisan, regime: "Micro-social / micro-fiscal", nature: nature,
                    base: base, value: d(value), effectiveFrom: from2026, effectiveTo: nil, sourceName: sp, sourceURL: url,
                    verifiedOn: checked, confidence: conf, note: note)
        }
        let caEnc = "Chiffre d'affaires HT encaissé sur la période déclarée"
        return TaxRuleSet(version: 1, rules: [
            r("cot-vente-2026", .cotisations, [.venteMarchandises], .rateOnCollectedRevenue, caEnc, "0.123", f36232),
            r("cot-bic-2026", .cotisations, [.prestationsBIC], .rateOnCollectedRevenue, caEnc, "0.212", f36232),
            r("cot-ssi-2026", .cotisations, [.liberaleSSI], .rateOnCollectedRevenue, caEnc, "0.256", f36232,
              .verified, "Taux affiché par service-public en 2026 (25,6 %). Certaines sources privées citent 26,1 % : vérifiez sur votre espace URSSAF."),
            r("cot-cipav-2026", .cotisations, [.liberaleCipav], .rateOnCollectedRevenue, caEnc, "0.232", f36232),
            r("vl-vente-2026", .versementLiberatoire, [.venteMarchandises], .rateOnCollectedRevenue, caEnc, "0.01", f23267,
              .verified, "Option soumise à un plafond de revenu fiscal de référence N-2."),
            r("vl-bic-2026", .versementLiberatoire, [.prestationsBIC], .rateOnCollectedRevenue, caEnc, "0.017", f23267),
            r("vl-bnc-2026", .versementLiberatoire, [.liberaleSSI, .liberaleCipav], .rateOnCollectedRevenue, caEnc, "0.022", f23267),
            r("cfp-commerce-2026", .cfp, [.venteMarchandises, .prestationsBIC], artisan: false, .rateOnCollectedRevenue, caEnc, "0.001", f23459,
              .toVerify, "Service-public indique un calcul sur le CA annuel et un versement en novembre ; le portail autoentrepreneur l'intègre aux déclarations périodiques. Le calendrier exact est à confirmer sur votre espace URSSAF."),
            r("cfp-artisan-2026", .cfp, [.venteMarchandises, .prestationsBIC], artisan: true, .rateOnCollectedRevenue, caEnc, "0.003", f23459,
              .toVerify, "Voir la note sur le calendrier de la CFP."),
            r("cfp-liberal-2026", .cfp, [.liberaleSSI, .liberaleCipav], .rateOnCollectedRevenue, caEnc, "0.002", f23459,
              .toVerify, "Voir la note sur le calendrier de la CFP."),
            r("abat-vente-2026", .abattement, [.venteMarchandises], .allowance, "CA annuel déclaré sur la déclaration de revenus", "0.71", f23267,
              .verified, "Abattement minimal de 305 €."),
            r("abat-bic-2026", .abattement, [.prestationsBIC], .allowance, "CA annuel déclaré sur la déclaration de revenus", "0.50", f23267),
            r("abat-bnc-2026", .abattement, [.liberaleSSI, .liberaleCipav], .allowance, "Recettes annuelles déclarées", "0.34", f23267),
            r("plafond-vente-2026", .microThreshold, [.venteMarchandises], .threshold, "CA annuel HT", "203100", f23267),
            r("plafond-services-2026", .microThreshold, [.prestationsBIC, .liberaleSSI, .liberaleCipav], .threshold, "CA annuel HT", "83600", f23267),
            r("tva-base-vente-2026", .vatThresholdBase, [.venteMarchandises], .threshold, "CA de l'année N-1", "85000", f21746),
            r("tva-base-services-2026", .vatThresholdBase, [.prestationsBIC, .liberaleSSI, .liberaleCipav], .threshold, "CA de l'année N-1", "37500", f21746),
            r("tva-maj-vente-2026", .vatThresholdMajore, [.venteMarchandises], .threshold, "CA de l'année en cours", "93500", f21746,
              .verified, "Dépassement : TVA due dès le premier jour du dépassement."),
            r("tva-maj-services-2026", .vatThresholdMajore, [.prestationsBIC, .liberaleSSI, .liberaleCipav], .threshold, "CA de l'année en cours", "41250", f21746,
              .verified, "Dépassement : TVA due dès le premier jour du dépassement."),
            r("vl-rfr-2026", .vlIncomeLimitSingle, [], .threshold, "Revenu fiscal de référence N-2 du foyer, personne seule", "29579", f23267,
              .verified, "59 158 € pour un couple, 73 947,50 € avec 1 enfant, 88 737 € avec 2 enfants."),
        ])
    }()
}

/// Calendrier officiel des échéances (fiche F23257) : déclarations mensuelles le dernier jour du mois suivant,
/// trimestrielles les 30 avril, 31 juillet, 31 octobre et 31 janvier ; report au jour ouvré suivant.
public enum FrenchCalendar {
    public static func isHoliday(_ date: Date, calendar: Calendar = .fr) -> Bool {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let fixed: Set<[Int]> = [[1, 1], [5, 1], [5, 8], [7, 14], [8, 15], [11, 1], [11, 11], [12, 25]]
        if fixed.contains([c.month!, c.day!]) { return true }
        // Lundi de Pâques, Ascension, lundi de Pentecôte
        let easter = easterSunday(year: c.year!, calendar: calendar)
        for offset in [1, 39, 50] {
            if calendar.isDate(date, inSameDayAs: calendar.date(byAdding: .day, value: offset, to: easter)!) { return true }
        }
        return false
    }

    public static func nextBusinessDay(onOrAfter date: Date, calendar: Calendar = .fr) -> Date {
        var d = date
        while calendar.isDateInWeekend(d) || isHoliday(d, calendar: calendar) {
            d = calendar.date(byAdding: .day, value: 1, to: d)!
        }
        return d
    }

    static func easterSunday(year y: Int, calendar: Calendar) -> Date {
        let a = y % 19, b = y / 100, c = y % 100, d = b / 4, e = b % 4
        let f = (b + 8) / 25, g = (b - f + 1) / 3, h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4, l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31, day = ((h + l - 7 * m + 114) % 31) + 1
        return calendar.date(y, month, day)
    }
}
