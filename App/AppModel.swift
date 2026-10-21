import SwiftUI
import CockpitCore
import WidgetKit
import UserNotifications

enum Screen: String, Hashable, CaseIterable, Identifiable {
    case today, forecast, insights, invoices, quotes, clients, missions, expenses, obligations, importBank, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: "Aujourd'hui"; case .forecast: "Prévisions"; case .insights: "Conseils"
        case .invoices: "Factures"; case .quotes: "Devis"; case .clients: "Clients"; case .missions: "Missions"
        case .expenses: "Dépenses"; case .obligations: "Réserves & impôts"; case .importBank: "Import bancaire"; case .settings: "Réglages"
        }
    }
    var symbol: String {
        switch self {
        case .today: "house"; case .forecast: "chart.line.uptrend.xyaxis"; case .insights: "lightbulb"
        case .invoices: "doc.text"; case .quotes: "doc.plaintext"; case .clients: "person.2"; case .missions: "briefcase"
        case .expenses: "creditcard"; case .obligations: "building.columns"; case .importBank: "square.and.arrow.down"; case .settings: "gearshape"
        }
    }
}

enum PeriodChoice: String, CaseIterable, Identifiable {
    case month, quarter, year, custom
    var id: String { rawValue }
    var label: String { switch self { case .month: "Mois"; case .quarter: "Trimestre"; case .year: "Année"; case .custom: "Personnalisée" } }
}

@MainActor
@Observable
final class AppModel {
    private(set) var ledger = Ledger()
    let store: LedgerStore?
    var loadError: String?
    var actionError: String?
    var toast: String?
    var screen: Screen? = .today
    var invoiceFilter: InvoiceFilter = .all
    var selectedInvoice: UUID?
    var periodChoice: PeriodChoice = .month
    var customPeriod = Period(start: Calendar.fr.startOfMonth(Date()), end: Date())
    var forecastAssumptions = ForecastAssumptions()
    var showOnboarding = false
    /// Création demandée depuis un autre écran : consommée par l'écran cible quand il apparaît.
    var pendingNew: Screen?
    func requestNew(_ s: Screen) { screen = s; pendingNew = s }
    var lastSaved: Date?
    /// Badges de la barre latérale, recalculés seulement quand les données changent.
    private(set) var urgentInsights = 0
    private(set) var obligationsToHandle = 0
    private let fixedToday: Date?

    enum InvoiceFilter: String, CaseIterable, Identifiable {
        case all, unpaid, overdue, drafts, paid
        var id: String { rawValue }
        var label: String { switch self { case .all: "Toutes"; case .unpaid: "À encaisser"; case .overdue: "En retard"; case .drafts: "Brouillons"; case .paid: "Payées" } }
    }

    init() {
        let args = ProcessInfo.processInfo.arguments
        func arg(_ name: String) -> String? { args.firstIndex(of: name).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
        fixedToday = arg("-cockpitToday").flatMap { CSVImporter.parseDate($0) }
        let dir = arg("-cockpitDataDir").map { URL(fileURLWithPath: $0, isDirectory: true) } ?? LedgerStore.defaultDirectory()
        let s = try? LedgerStore(directory: dir)
        store = s
        do {
            if let s {
                ledger = try s.load()
                if args.contains("-cockpitSample") && ledger.invoices.isEmpty { ledger = SampleData.ledger(today: fixedToday ?? Date()); try? s.save(ledger) }
            } else { loadError = "Impossible de créer le dossier de données." }
        } catch {
            loadError = error.localizedDescription
        }
        showOnboarding = !ledger.profile.onboardingCompleted && loadError == nil
        customPeriod = Period(start: Calendar.fr.startOfMonth(today), end: today)
        publishSnapshot()
    }

    var today: Date { fixedToday ?? Date() }
    var finance: FinanceEngine { FinanceEngine(ledger: ledger, today: today) }
    var forecast: ForecastEngine { ForecastEngine(finance: finance, assumptions: forecastAssumptions) }

    var period: Period {
        switch periodChoice {
        case .month: .month(of: today)
        case .quarter: .quarter(of: today)
        case .year: .year(of: today)
        case .custom: customPeriod
        }
    }

    // MARK: Mutations

    /// Toute modification passe ici : validation, sauvegarde atomique, widget.
    @discardableResult
    func update(_ success: String? = nil, _ change: (inout Ledger) throws -> Void) -> Bool {
        var copy = ledger
        do {
            try change(&copy)
            ledger = copy
            try store?.save(ledger)
            lastSaved = Date()
            publishSnapshot()
            if let success { toast = success }
            return true
        } catch {
            actionError = error.localizedDescription
            return false
        }
    }

    func refreshBadges() {
        let fin = finance
        urgentInsights = InsightEngine(finance: fin, forecast: forecast).insights().filter { $0.urgency >= 2 }.count
        obligationsToHandle = fin.allObligations().filter { ($0.status == .toDeclare || $0.status == .toVerify) && $0.period.start <= today }.count
    }

    func publishSnapshot() {
        refreshBadges()
        let snap = WidgetSnapshot.make(from: ledger, today: today)
        if SharedSnapshot.write(snap) { WidgetCenter.shared.reloadAllTimelines() }
    }

    var widgetSharingAvailable: Bool { SharedSnapshot.fileURL != nil }

    // MARK: Navigation (liens profonds du widget)

    func open(_ url: URL) {
        guard url.scheme == "cockpit" else { return }
        switch url.host {
        case "today": screen = .today
        case "forecast": screen = .forecast
        case "obligations": screen = .obligations
        case "invoices":
            screen = .invoices
            let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "filter" }?.value
            invoiceFilter = q.flatMap(InvoiceFilter.init(rawValue:)) ?? .all
            if let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value.flatMap(UUID.init) {
                invoiceFilter = .all; selectedInvoice = id
            }
        default: screen = .today
        }
    }

    // MARK: Données

    func backupNow() {
        do { let url = try store?.backupNow(ledger); toast = "Sauvegarde créée : \(url?.lastPathComponent ?? "")" }
        catch { actionError = error.localizedDescription }
    }

    func restore(from url: URL) {
        guard let store else { return }
        do { ledger = try store.restore(from: url); publishSnapshot(); toast = "Données restaurées." }
        catch { actionError = error.localizedDescription }
    }

    func loadSample() {
        update("Données d'exemple chargées. Tu peux les effacer depuis Réglages › Données.") { $0 = SampleData.ledger(today: today) }
        showOnboarding = false
    }

    func resetAll() {
        backupNow()
        update("Toutes les données ont été effacées. Une sauvegarde a été faite juste avant.") { l in
            let rules = l.rules
            l = Ledger(); l.rules = rules
        }
        showOnboarding = true
    }

    // MARK: Notifications locales (facultatives)

    func scheduleDeadlineNotifications() async {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else {
            toast = "Notifications refusées : tu peux les activer dans Réglages Système."
            return
        }
        center.removeAllPendingNotificationRequests()
        for d in finance.upcoming(days: 60) {
            guard let fire = Calendar.fr.date(byAdding: .day, value: -5, to: d.date), fire > Date() else { continue }
            let content = UNMutableNotificationContent()
            content.title = d.title
            content.body = "Échéance le \(d.date.long)."
            var comps = Calendar.fr.dateComponents([.year, .month, .day], from: fire); comps.hour = 9
            try? await center.add(UNNotificationRequest(identifier: d.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
        toast = "Rappels programmés 5 jours avant chaque échéance."
    }
}
