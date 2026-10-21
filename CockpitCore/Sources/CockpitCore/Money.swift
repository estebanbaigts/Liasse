import Foundation

/// Montant monétaire exact, stocké en centimes d'euro (entier 64 bits).
/// Aucun calcul monétaire ne passe par Double : les taux s'appliquent via `Decimal`
/// avec un arrondi explicite au centime (demi-supérieur, comme sur les déclarations).
public struct Money: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public var cents: Int64

    public init(cents: Int64) { self.cents = cents }
    public init(euros: Int) { self.cents = Int64(euros) * 100 }

    /// Construit un montant à partir d'un Decimal en euros, arrondi au centime.
    public init(decimalEuros: Decimal) {
        var value = decimalEuros * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        self.cents = NSDecimalNumber(decimal: rounded).int64Value
    }

    public static let zero = Money(cents: 0)

    public var decimal: Decimal { Decimal(cents) / 100 }
    public var isZero: Bool { cents == 0 }
    public var isNegative: Bool { cents < 0 }
    public var isPositive: Bool { cents > 0 }

    public static func + (l: Money, r: Money) -> Money { Money(cents: l.cents + r.cents) }
    public static func - (l: Money, r: Money) -> Money { Money(cents: l.cents - r.cents) }
    public static prefix func - (m: Money) -> Money { Money(cents: -m.cents) }
    public static func += (l: inout Money, r: Money) { l.cents += r.cents }
    public static func -= (l: inout Money, r: Money) { l.cents -= r.cents }
    public static func < (l: Money, r: Money) -> Bool { l.cents < r.cents }

    /// Applique un taux (ex. 0.256 pour 25,6 %) avec arrondi au centime.
    public func applying(rate: Decimal) -> Money { Money(decimalEuros: decimal * rate) }

    /// Multiplie par une quantité décimale (ex. 2,5 jours).
    public func times(_ quantity: Decimal) -> Money { Money(decimalEuros: decimal * quantity) }

    public func clamped(min lower: Money) -> Money { self < lower ? lower : self }

    public var description: String { MoneyFormat.string(self) }
}

extension Sequence {
    public func sum(_ value: (Element) -> Money) -> Money {
        reduce(.zero) { $0 + value($1) }
    }
}

public enum MoneyFormat {
    public static func string(_ m: Money, showCents: Bool = true) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.numberStyle = .currency
        f.currencyCode = "EUR"
        f.maximumFractionDigits = showCents ? 2 : 0
        f.minimumFractionDigits = showCents ? 2 : 0
        return f.string(from: NSDecimalNumber(decimal: m.decimal)) ?? "\(m.decimal) €"
    }

    /// Analyse une saisie utilisateur ou CSV : "1 234,56", "1234.56", "-12,5 €", "1.234,56".
    public static func parse(_ raw: String) -> Money? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "EUR", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard !s.isEmpty else { return nil }
        var negative = false
        if s.hasPrefix("(") && s.hasSuffix(")") { negative = true; s = String(s.dropFirst().dropLast()) }
        if s.hasPrefix("-") { negative = true; s.removeFirst() } else if s.hasPrefix("+") { s.removeFirst() }
        let lastComma = s.lastIndex(of: ",")
        let lastDot = s.lastIndex(of: ".")
        if let c = lastComma, let d = lastDot {
            if c > d { s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
            else { s = s.replacingOccurrences(of: ",", with: "") }
        } else if lastComma != nil {
            s = s.replacingOccurrences(of: ",", with: ".")
        }
        guard s.allSatisfy({ $0.isNumber || $0 == "." }), s.filter({ $0 == "." }).count <= 1,
              let d = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        let m = Money(decimalEuros: d)
        return negative ? -m : m
    }

    public static func percent(_ rate: Decimal, digits: Int = 1) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.numberStyle = .percent
        f.maximumFractionDigits = digits
        f.minimumFractionDigits = 0
        return f.string(from: NSDecimalNumber(decimal: rate)) ?? "\(rate)"
    }
}
