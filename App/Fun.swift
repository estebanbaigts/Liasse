import SwiftUI
import CockpitCore

// MARK: - Briques visuelles « vivantes »

/// Pastille colorée contenant un symbole (barre latérale, lignes, cartes).
struct IconBubble: View {
    let symbol: String
    var tint: Color = .accentColor
    var size: CGFloat = 28
    var filled = false
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .semibold, design: .rounded))
            .foregroundStyle(filled ? .white : tint)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .fill(filled ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.opacity(0.16)))
            )
            .accessibilityHidden(true)
    }
}

/// Carte douce : coins arrondis, fond légèrement teinté, ombre portée discrète.
struct Card<Content: View>: View {
    var tint: Color? = nil
    var padding: CGFloat = DS.Space.l
    @ViewBuilder var content: () -> Content
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                    .fill(DS.cardFill)
                    .overlay {
                        if let tint {
                            RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                                .fill(LinearGradient(colors: [tint.opacity(0.12), tint.opacity(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                    }
                    .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.06), radius: 14, x: 0, y: 6)
            }
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous).strokeBorder(DS.hairline))
    }
}

/// Soulève légèrement un élément cliquable au survol.
struct HoverLift: ViewModifier {
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View {
        content
            .scaleEffect(hover && !reduce ? 1.015 : 1)
            .offset(y: hover && !reduce ? -2 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hover)
            .onHover { hover = $0 }
    }
}

/// Apparition en cascade à l'ouverture d'un écran.
struct Appear: ViewModifier {
    var index: Int = 0
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View {
        content
            .opacity(shown || reduce ? 1 : 0)
            .offset(y: shown || reduce ? 0 : 12)
            .onAppear {
                guard !reduce else { shown = true; return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(Double(index) * 0.06)) { shown = true }
            }
    }
}

extension View {
    func hoverLift() -> some View { modifier(HoverLift()) }
    func appear(_ index: Int = 0) -> some View { modifier(Appear(index: index)) }
}

/// Montant qui défile jusqu'à sa valeur à l'affichage (et à chaque changement).
struct CountingAmount: View {
    let money: Money
    var font: Font = DS.Font.hero
    var color: Color = .primary
    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        Text(MoneyFormat.string(Money(decimalEuros: Decimal(shown)), showCents: true))
            .font(font)
            .foregroundStyle(color)
            .contentTransition(.numericText(value: shown))
            .monospacedDigit()
            .accessibilityLabel(money.description)
            .onAppear { animate() }
            .onChange(of: money) { animate() }
    }

    func animate() {
        let target = NSDecimalNumber(decimal: money.decimal).doubleValue
        if reduce { shown = target; return }
        withAnimation(.spring(response: 0.9, dampingFraction: 0.9)) { shown = target }
    }
}

/// Anneau de progression animé (objectif du mois).
struct ProgressRing: View {
    let progress: Double
    var tint: Color = DS.income
    var lineWidth: CGFloat = 10
    @State private var drawn: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(drawn, 0), 1))
                .stroke(AngularGradient(colors: [tint.opacity(0.7), tint], center: .center), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .onAppear { if reduce { drawn = progress } else { withAnimation(.easeOut(duration: 1.1).delay(0.2)) { drawn = progress } } }
        .onChange(of: progress) { withAnimation(.easeOut(duration: 0.6)) { drawn = progress } }
    }
}

/// Initiales du client dans une pastille de couleur stable (dérivée du nom).
struct Avatar: View {
    let name: String
    var size: CGFloat = 32
    static let palette: [Color] = [DS.brandA, DS.brandB, DS.brandC, DS.income, DS.due, DS.reserve, .teal, .pink]
    var color: Color {
        let h = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Self.palette[h % Self.palette.count]
    }
    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
    var body: some View {
        Text(initials.isEmpty ? "?" : initials)
            .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(color.gradient))
            .accessibilityHidden(true)
    }
}

/// Fond animé lent de la carte d'accueil (dégradé maillé). Figé si « Réduire les animations ».
struct LivelyBackground: View {
    var colors: [Color]
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduce)) { context in
            let t = reduce ? 0 : context.date.timeIntervalSinceReferenceDate
            let s = Float(sin(t * 0.35)) * 0.12, c = Float(cos(t * 0.28)) * 0.12
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.5 + s, 0.5 + c], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1]
            ], colors: colors)
        }
    }
}

/// Petite pluie de confettis — célébration d'une facture soldée.
struct ConfettiBurst: View {
    let trigger: Int
    @State private var start: Date?
    @Environment(\.accessibilityReduceMotion) private var reduce
    let pieces: [(x: Double, speed: Double, spin: Double, color: Color, size: Double, delay: Double)] = (0..<70).map { _ in
        (Double.random(in: 0...1), Double.random(in: 180...420), Double.random(in: -6...6),
         [DS.brandA, DS.brandB, DS.brandC, DS.income, DS.due, .yellow].randomElement()!, Double.random(in: 5...10), Double.random(in: 0...0.25))
    }

    var body: some View {
        TimelineView(.animation(paused: start == nil)) { ctx in
            Canvas { gc, size in
                guard let start else { return }
                let t = ctx.date.timeIntervalSince(start)
                for p in pieces {
                    let lt = t - p.delay
                    guard lt > 0, lt < 2.2 else { continue }
                    let x = p.x * size.width + sin(lt * 3 + p.spin) * 18
                    let y = -20 + p.speed * lt + 160 * lt * lt
                    var g = gc
                    g.opacity = max(0, 1 - lt / 2.2)
                    g.translateBy(x: x, y: y)
                    g.rotate(by: .radians(lt * p.spin))
                    g.fill(Path(roundedRect: CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.size / 2), cornerRadius: 1.5), with: .color(p.color))
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) {
            guard !reduce else { return }
            start = Date()
            Task { try? await Task.sleep(for: .seconds(2.6)); start = nil }
        }
        .accessibilityHidden(true)
    }
}

/// Bonjour / Bon après-midi / Bonsoir selon l'heure.
func greeting(for date: Date, name: String) -> String {
    let h = Calendar.fr.component(.hour, from: date)
    let first = name.split(separator: " ").first.map(String.init) ?? ""
    let hello = h < 5 ? "Bonne nuit" : (h < 12 ? "Bonjour" : (h < 18 ? "Bon après-midi" : "Bonsoir"))
    return first.isEmpty ? hello : "\(hello) \(first)"
}

extension ExpenseCategory {
    var symbol: String {
        switch self {
        case .software: "app.badge"; case .hardware: "desktopcomputer"; case .office: "paperclip"
        case .travel: "tram.fill"; case .meals: "fork.knife"; case .training: "graduationcap.fill"; case .insurance: "shield.lefthalf.filled"
        case .bank: "building.columns.fill"; case .telecom: "antenna.radiowaves.left.and.right"; case .fees: "person.text.rectangle"
        case .subcontracting: "person.2.fill"; case .taxes: "percent"; case .other: "square.grid.2x2"; case .unclassified: "questionmark.circle"
        }
    }
    var tint: Color {
        switch self {
        case .software: DS.brandA; case .hardware: DS.due; case .office: .teal; case .travel: DS.brandC; case .meals: DS.brandB
        case .training: DS.income; case .insurance: .indigo; case .bank: .gray; case .telecom: .cyan; case .fees: .purple
        case .subcontracting: .mint; case .taxes: DS.reserve; case .other: .secondary; case .unclassified: DS.outflow
        }
    }
}

extension ObligationKind {
    var symbol: String {
        switch self {
        case .cotisations: "person.crop.circle.badge.checkmark"; case .cfp: "graduationcap"; case .versementLiberatoire: "doc.text.fill"
        case .incomeTax: "building.columns"; case .vat: "percent"; case .cfe: "house.fill"
        }
    }
}

extension Screen {
    var tint: Color {
        switch self {
        case .today: DS.brandA; case .forecast: DS.due; case .insights: .yellow
        case .invoices: DS.brandB; case .quotes: .pink; case .clients: .teal; case .missions: DS.brandC
        case .expenses: DS.outflow; case .obligations: DS.reserve; case .importBank: .cyan; case .settings: .gray
        }
    }
    var filledSymbol: String {
        switch self {
        case .today: "house.fill"; case .forecast: "chart.line.uptrend.xyaxis"; case .insights: "lightbulb.fill"
        case .invoices: "doc.text.fill"; case .quotes: "doc.plaintext.fill"; case .clients: "person.2.fill"; case .missions: "briefcase.fill"
        case .expenses: "creditcard.fill"; case .obligations: "building.columns.fill"; case .importBank: "square.and.arrow.down.fill"; case .settings: "gearshape.fill"
        }
    }
}
