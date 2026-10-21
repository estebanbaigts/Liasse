import SwiftUI
import CockpitCore

/// Tokens de design — direction « vivante » : couleurs chaudes, formes douces, police arrondie.
/// Chaque couleur garde un sens unique (encaissé, réserve, dépense/retard, échéance) et n'est jamais seule porteuse d'information.
enum DS {
    enum Space {
        static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 20, xl: CGFloat = 28, xxl: CGFloat = 40
        static let page: CGFloat = 30
    }
    enum Radius { static let s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 18, xl: CGFloat = 26 }

    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }
    static func rgb(_ r: Double, _ g: Double, _ b: Double) -> NSColor { NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1) }

    /// Encaissé, disponible — vert menthe.
    static let income = dynamic(light: rgb(14, 150, 104), dark: rgb(52, 211, 153))
    /// Réserves et obligations — orange mandarine.
    static let reserve = dynamic(light: rgb(214, 104, 0), dark: rgb(255, 166, 61))
    /// Dépenses et retards — corail.
    static let outflow = dynamic(light: rgb(222, 56, 74), dark: rgb(255, 107, 122))
    /// Échéances — violet indigo.
    static let due = dynamic(light: rgb(88, 86, 214), dark: rgb(150, 148, 255))
    /// Marque : violet → rose → pêche.
    static let brandA = dynamic(light: rgb(124, 77, 255), dark: rgb(146, 110, 255))
    static let brandB = dynamic(light: rgb(255, 79, 154), dark: rgb(255, 102, 170))
    static let brandC = dynamic(light: rgb(255, 160, 90), dark: rgb(255, 170, 110))
    static var brand: LinearGradient { LinearGradient(colors: [brandA, brandB, brandC], startPoint: .topLeading, endPoint: .bottomTrailing) }

    static let hairline = Color.primary.opacity(0.08)
    static let cardFill = dynamic(light: NSColor(white: 1, alpha: 1), dark: NSColor(white: 1, alpha: 0.055))
    static let canvas = dynamic(light: rgb(246, 245, 250), dark: rgb(24, 23, 28))

    enum Font {
        static let sentence = SwiftUI.Font.system(size: 30, weight: .bold, design: .rounded).leading(.tight)
        static let hero = SwiftUI.Font.system(size: 52, weight: .heavy, design: .rounded).monospacedDigit()
        static let figure = SwiftUI.Font.system(size: 21, weight: .bold, design: .rounded).monospacedDigit()
        static let figureLarge = SwiftUI.Font.system(size: 28, weight: .bold, design: .rounded).monospacedDigit()
        static let section = SwiftUI.Font.system(.title3, design: .rounded).weight(.bold)
        static let label = SwiftUI.Font.callout
    }

    static let animation: Animation = .spring(response: 0.38, dampingFraction: 0.78)
}

extension View {
    /// Animation respectant « Réduire les animations ».
    func dsAnimation<V: Equatable>(_ value: V) -> some View { modifier(ReducedMotionAnimation(value: value)) }
}

struct ReducedMotionAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) var reduce
    let value: V
    func body(content: Content) -> some View { content.animation(reduce ? nil : DS.animation, value: value) }
}

// MARK: - Composants

struct Amount: View {
    let money: Money
    var font: Font = .body.monospacedDigit()
    var color: Color? = nil
    var signed = false
    var body: some View {
        Text((signed && money.isPositive ? "+" : "") + money.description)
            .font(font).monospacedDigit()
            .foregroundStyle(color ?? .primary)
            .contentTransition(.numericText())
            .accessibilityLabel(Text(money.description))
    }
}

/// Signale une estimation : jamais confondue avec un montant officiel.
struct EstimateBadge: View {
    var text = "estimation"
    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2])).foregroundStyle(.tertiary))
            .accessibilityLabel("Estimation")
    }
}

struct StatusTag: View {
    let text: String
    let color: Color
    var symbol: String? = nil
    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.caption2.weight(.bold)) }
            Text(text).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 9).padding(.vertical, 3)
        .background(color.opacity(0.16), in: Capsule())
        .foregroundStyle(color)
    }
}

extension InvoiceStatus {
    var symbol: String {
        switch self {
        case .draft: "pencil"; case .issued: "paperplane.fill"; case .partiallyPaid: "circle.lefthalf.filled"
        case .paid: "checkmark"; case .overdue: "exclamationmark"; case .cancelled: "xmark"
        }
    }
    var color: Color {
        switch self {
        case .draft: .secondary; case .issued: DS.due; case .partiallyPaid: DS.reserve
        case .paid: DS.income; case .overdue: DS.outflow; case .cancelled: .secondary
        }
    }
}

extension ObligationStatus {
    var symbol: String {
        switch self {
        case .provisional: "hourglass"; case .toDeclare: "square.and.pencil"; case .declared, .toPay: "creditcard"
        case .paid: "checkmark"; case .toVerify: "questionmark"
        }
    }
    var color: Color {
        switch self {
        case .provisional: .secondary; case .toDeclare: DS.due; case .declared, .toPay: DS.reserve
        case .paid: DS.income; case .toVerify: DS.outflow
        }
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action { Button(actionTitle, action: action).buttonStyle(.borderedProminent) }
        }
        // Sans cette contrainte, la hauteur idéale de ContentUnavailableView peut dépasser la fenêtre
        // et décaler toute la mise en page (barre latérale comprise).
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }
}

/// Titre de section : poids, jamais d'étiquette au-dessus.
struct SectionTitle: View {
    let text: String
    var trailing: AnyView? = nil
    init(_ text: String, trailing: AnyView? = nil) { self.text = text; self.trailing = trailing }
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).font(DS.Font.section)
            Spacer()
            trailing
        }
        .padding(.bottom, DS.Space.xs)
    }
}

/// Une ligne : libellé, détail, montant. Légère mise en avant au survol.
struct LedgerRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var symbol: String? = nil
    var tint: Color = .accentColor
    @ViewBuilder var trailing: () -> Trailing
    @State private var hover = false
    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.m) {
            if let symbol { IconBubble(symbol: symbol, tint: tint, size: 30) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium).lineLimit(1)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: DS.Space.m)
            HStack(spacing: DS.Space.s) { trailing() }.fixedSize()
        }
        .padding(.vertical, 8).padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous).fill(hover ? Color.primary.opacity(0.05) : .clear))
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
        .accessibilityElement(children: .combine)
    }
}

/// Champ monétaire : saisie française, validation immédiate.
struct MoneyField: View {
    let title: String
    @Binding var value: Money
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        TextField(title, text: $text, prompt: Text("0,00"))
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .focused($focused)
            .accessibilityLabel(title)
            .onAppear { text = format(value) }
            .onChange(of: value) { if !focused { text = format(value) } }
            .onChange(of: text) {
                if text.trimmingCharacters(in: .whitespaces).isEmpty { value = .zero }
                else if let m = MoneyFormat.parse(text) { value = m }
            }
            .onChange(of: focused) { if !focused { text = format(value) } }
    }
    func format(_ m: Money) -> String {
        let f = NumberFormatter(); f.locale = Locale(identifier: "fr_FR"); f.minimumFractionDigits = 2; f.maximumFractionDigits = 2
        return f.string(from: NSDecimalNumber(decimal: m.decimal)) ?? ""
    }
}

struct DecimalField: View {
    let title: String
    @Binding var value: Decimal
    var percent = false
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        TextField(title, text: $text, prompt: Text("0"))
            .labelsHidden()
            .multilineTextAlignment(.trailing).monospacedDigit().focused($focused)
            .accessibilityLabel(title)
            .onAppear { text = format() }
            .onChange(of: focused) { if !focused { text = format() } }
            .onChange(of: text) {
                let s = text.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
                if let d = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) { value = percent ? d / 100 : d }
            }
    }
    func format() -> String {
        let v = percent ? value * 100 : value
        let f = NumberFormatter(); f.locale = Locale(identifier: "fr_FR"); f.maximumFractionDigits = 3
        return f.string(from: NSDecimalNumber(decimal: v)) ?? ""
    }
}

extension Date {
    var short: String { formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_FR"))) }
    var long: String { formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "fr_FR"))) }
    var weekdayLong: String { formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_FR"))).capitalized(with: Locale(identifier: "fr_FR")) }
}

extension LocalizedStringKey.StringInterpolation {
    /// Les montants s'insèrent dans les textes avec leur format français (1 234,56 €).
    mutating func appendInterpolation(_ m: Money) { appendLiteral(m.description) }
}
