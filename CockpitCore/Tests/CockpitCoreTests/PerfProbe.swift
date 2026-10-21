import Foundation
import Testing
@testable import CockpitCore

@Suite("Mesure") struct PerfProbe {
    func time(_ label: String, _ n: Int = 20, _ f: () -> Void) {
        let t = Date(); for _ in 0..<n { f() }
        print("⏱ \(label): \(String(format: "%.2f", Date().timeIntervalSince(t) / Double(n) * 1000)) ms")
    }
    @Test func probe() {
        let l = SampleData.ledger(today: cal.date(2026, 10, 21))
        let fin = FinanceEngine(ledger: l, today: cal.date(2026, 10, 21))
        time("money format x100") { for i in 0..<100 { _ = Money(cents: Int64(i)).description } }
        time("dashboard") { _ = fin.dashboard(period: .month(of: cal.date(2026, 10, 21))) }
        time("dashboard (moteur neuf)") { _ = FinanceEngine(ledger: l, today: cal.date(2026, 10, 21)).dashboard(period: .month(of: cal.date(2026, 10, 21))) }
        time("insights (moteur neuf)") { let f = FinanceEngine(ledger: l, today: cal.date(2026, 10, 21)); _ = InsightEngine(finance: f, forecast: ForecastEngine(finance: f)).insights() }
        time("allObligations") { _ = fin.allObligations() }
        time("forecast x3") { let fe = ForecastEngine(finance: fin); for s in Scenario.allCases { _ = fe.run(s) } }
        time("insights") { _ = InsightEngine(finance: fin, forecast: ForecastEngine(finance: fin)).insights() }
        time("snapshot") { _ = WidgetSnapshot.make(from: l, today: cal.date(2026, 10, 21)) }
    }
}
