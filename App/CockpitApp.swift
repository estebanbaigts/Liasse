import SwiftUI
import CockpitCore

@main
struct CockpitApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Liasse", id: "main") {
            RootView()
                .environment(model)
                .onOpenURL { model.open($0) }
                .frame(minWidth: 940, minHeight: 600)
        }
        .defaultSize(width: 1180, height: 760)
        .defaultLaunchBehavior(.presented)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Nouvelle facture") { model.requestNew(.invoices) }
                    .keyboardShortcut("n")
                Button("Nouvelle dépense") { model.requestNew(.expenses) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandMenu("Aller à") {
                ForEach(Array(Screen.allCases.enumerated()), id: \.element) { i, s in
                    if i < 9 { Button(s.title) { model.screen = s }.keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command) }
                    else { Button(s.title) { model.screen = s } }
                }
            }
        }

        MenuBarExtra {
            MenuBarPanel().environment(model)
        } label: {
            Image(systemName: "eurosign.circle")
        }
        .menuBarExtraStyle(.window)
    }
}

extension Notification.Name {
    static let newInvoice = Notification.Name("cockpit.newInvoice")
    static let newExpense = Notification.Name("cockpit.newExpense")
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.screen) {
                Section {
                    row(.today); row(.forecast); row(.insights, badge: model.urgentInsights)
                }
                Section("Ventes") { row(.invoices, badge: model.finance.overdueInvoices.count); row(.quotes); row(.clients); row(.missions) }
                Section("Argent") { row(.expenses); row(.obligations, badge: model.obligationsToHandle); row(.importBank) }
                Section { row(.settings) }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 212, max: 280)
        } detail: {
            Group {
                switch model.screen ?? .today {
                case .today: DashboardView()
                case .forecast: ForecastView()
                case .insights: InsightsView()
                case .invoices: InvoicesView()
                case .quotes: QuotesView()
                case .clients: ClientsView()
                case .missions: MissionsView()
                case .expenses: ExpensesView()
                case .obligations: ObligationsView()
                case .importBank: ImportView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DS.canvas)
        }
        .fontDesign(.rounded)
        .tint(DS.brandA)
        .sheet(isPresented: $model.showOnboarding) { OnboardingView() }
        .alert("Action impossible", isPresented: Binding(get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.actionError ?? "") }
        .alert("Données illisibles", isPresented: Binding(get: { model.loadError != nil }, set: { if !$0 { model.loadError = nil } })) {
            Button("Ouvrir les réglages") { model.screen = .settings }
        } message: { Text(model.loadError ?? "") }
        .overlay(alignment: .bottom) { ToastView() }
        .onAppear {
            // Option de vérification visuelle : -cockpitAppearance light|dark
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-cockpitAppearance"), i + 1 < args.count {
                NSApp.appearance = NSAppearance(named: args[i + 1] == "light" ? .aqua : .darkAqua)
            }
        }
    }

    func row(_ s: Screen, badge: Int = 0) -> some View {
        Label { Text(s.title).fontWeight(.medium) } icon: { IconBubble(symbol: s.filledSymbol, tint: s.tint, size: 22, filled: true) }
            .badge(badge)
            .tag(s)
    }
}

struct ToastView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if let t = model.toast {
            Label(t, systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.medium))
                .symbolRenderingMode(.multicolor)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(DS.hairline))
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.9)))
                .task(id: t) { try? await Task.sleep(for: .seconds(3.5)); model.toast = nil }
                .accessibilityAddTraits(.isStaticText)
        }
    }
}

/// Mini-panneau de la barre des menus (direction 8).
struct MenuBarPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage("menuBarHideAmounts") private var hide = false

    var body: some View {
        let dash = model.finance.dashboard(period: .month(of: model.today))
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack {
                Text("Disponible ce mois").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button { hide.toggle() } label: { Image(systemName: hide ? "eye.slash" : "eye") }
                    .buttonStyle(.borderless).help(hide ? "Afficher les montants" : "Masquer les montants")
            }
            Text(hide ? "•••• €" : dash.available.description).font(DS.Font.figureLarge).foregroundStyle(DS.income)
            Divider()
            row("À réserver", dash.reserves.total, DS.reserve)
            row("On te doit", dash.receivables, nil)
            if let next = dash.upcoming.first {
                HStack { Text(next.title).lineLimit(1); Spacer(); Text(next.date.short).foregroundStyle(.secondary) }.font(.callout)
            }
            Divider()
            HStack {
                Button("Ouvrir Liasse") { NSApp.activate(); openWindow(id: "main") }
                Spacer()
                Button("Quitter") { NSApp.terminate(nil) }.buttonStyle(.borderless).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 290)
    }

    func row(_ label: String, _ m: Money, _ c: Color?) -> some View {
        HStack { Text(label); Spacer(); Text(hide ? "•••" : m.description).monospacedDigit().foregroundStyle(c ?? .primary) }.font(.callout)
    }
}
