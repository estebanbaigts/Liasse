import SwiftUI
import CockpitCore

struct ClientsView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var editing: Client?
    @State private var selection: UUID?

    var body: some View {
        let year = Period(start: Calendar.fr.date(byAdding: .month, value: -12, to: model.today)!, end: model.today)
        let stats = Dictionary(uniqueKeysWithValues: model.finance.clientStats(in: year).map { ($0.id, $0) })
        let clients = model.ledger.clients.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.email.localizedCaseInsensitiveContains(search) }
            .sorted { (stats[$0.id]?.collected ?? .zero) > (stats[$1.id]?.collected ?? .zero) }
        HStack(spacing: 0) {
            Group {
                if model.ledger.clients.isEmpty {
                    EmptyState(symbol: "person.2", title: "Aucun client", message: "Ajoute un client pour lui facturer tes prestations.", actionTitle: "Nouveau client") { editing = Client(name: "") }
                } else {
                    Table(clients, selection: $selection) {
                        TableColumn("Client") { Text($0.name).fontWeight(.medium) }
                        TableColumn("Encaissé 12 mois") { c in Amount(money: stats[c.id]?.collected ?? .zero).frame(maxWidth: .infinity, alignment: .trailing) }.width(130)
                        TableColumn("Part") { c in Text(MoneyFormat.percent(stats[c.id]?.share ?? 0, digits: 0)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing) }.width(60)
                        TableColumn("En attente") { c in Amount(money: stats[c.id]?.outstanding ?? .zero).frame(maxWidth: .infinity, alignment: .trailing) }.width(110)
                    }
                    .contextMenu(forSelectionType: UUID.self) { ids in
                        if let id = ids.first, let c = model.ledger.client(id) { Button("Modifier…") { editing = c } }
                    } primaryAction: { ids in if let id = ids.first { editing = model.ledger.client(id) } }
                }
            }
            .frame(maxWidth: .infinity)
            if let id = selection, let c = model.ledger.client(id) {
                Divider()
                ClientHistory(client: c).frame(width: 320)
            }
        }
        .navigationTitle("Clients")
        .searchable(text: $search, prompt: "Nom ou e-mail")
        .toolbar { ToolbarItem { Button { editing = Client(name: "") } label: { Label("Nouveau client", systemImage: "plus") } } }
        .sheet(item: $editing) { ClientEditor(client: $0) }
    }
}

struct ClientHistory: View {
    @Environment(AppModel.self) private var model
    let client: Client
    var body: some View {
        let invs = model.ledger.invoices.filter { $0.clientId == client.id }.sorted { $0.issueDate > $1.issueDate }
        let quotes = model.ledger.quotes.filter { $0.clientId == client.id }
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(client.name).font(.title3.weight(.semibold))
                    if !client.email.isEmpty { Text(client.email).foregroundStyle(.secondary) }
                    if !client.address.isEmpty { Text(client.address).font(.callout).foregroundStyle(.secondary) }
                }
                VStack(alignment: .leading, spacing: 0) {
                    SectionTitle("Factures et paiements")
                    if invs.isEmpty { Text("Aucune facture.").foregroundStyle(.secondary) }
                    ForEach(invs) { inv in
                        Button { model.selectedInvoice = inv.id; model.invoiceFilter = .all; model.screen = .invoices } label: {
                            LedgerRow(title: inv.number ?? "Brouillon", subtitle: "\(inv.issueDate.short) · \(inv.status(on: model.today).label) · payé \(inv.paidAmount)") { Amount(money: inv.totals.ttc) }
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
                if !quotes.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionTitle("Devis")
                        ForEach(quotes) { q in LedgerRow(title: q.number ?? "Brouillon", subtitle: q.status.label) { Amount(money: q.totals.ttc) } }
                    }
                }
            }
            .padding(DS.Space.l)
        }
    }
}

struct ClientEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var client: Client
    var onSave: ((Client) -> Void)? = nil
    @State private var confirmDelete = false

    var body: some View {
        let exists = model.ledger.client(client.id) != nil
        let hasInvoices = model.ledger.invoices.contains { $0.clientId == client.id }
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    TextField("Nom ou raison sociale", text: $client.name)
                    Toggle("Entreprise", isOn: $client.isCompany)
                    TextField("Contact (prénom utilisé dans les relances)", text: $client.contactName)
                    TextField("E-mail de facturation", text: $client.email)
                    TextField("Adresse", text: $client.address, axis: .vertical).lineLimit(2...4)
                }
                if client.isCompany {
                    Section("Informations professionnelles") {
                        TextField("SIREN", text: $client.siren)
                        TextField("N° de TVA intracommunautaire", text: $client.vatNumber)
                    }
                }
                Section { TextField("Notes internes", text: $client.notes, axis: .vertical).lineLimit(2...4) }
            }
            .formStyle(.grouped)
            HStack {
                if exists {
                    Button("Supprimer", role: .destructive) { confirmDelete = true }
                        .disabled(hasInvoices).help(hasInvoices ? "Un client facturé doit être conservé avec ses factures." : "")
                }
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Enregistrer") {
                    let c = client
                    model.update("Client enregistré.") { l in
                        if let i = l.clients.firstIndex(where: { $0.id == c.id }) { l.clients[i] = c } else { l.clients.append(c) }
                    }
                    onSave?(c); dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(client.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(DS.Space.m)
        }
        .frame(width: 460, height: 520)
        .confirmationDialog("Supprimer \(client.name) ?", isPresented: $confirmDelete) {
            Button("Supprimer", role: .destructive) { let id = client.id; model.update("Client supprimé.") { $0.clients.removeAll { $0.id == id } }; dismiss() }
        }
    }
}

struct MissionsView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: Mission?
    @State private var goalNet: Money = Money(euros: 4000)

    var body: some View {
        let fin = model.finance
        let stats = fin.missionStats()
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                if stats.isEmpty {
                    EmptyState(symbol: "briefcase", title: "Aucune mission", message: "Une mission regroupe un client, un TJM et des jours : elle permet de suivre la rentabilité et le travail non facturé.",
                               actionTitle: "Nouvelle mission") { editing = Mission(title: "", clientId: model.ledger.clients.first?.id, dailyRate: model.ledger.profile.defaultDailyRate) }
                        .frame(height: 280)
                } else {
                    VStack(alignment: .leading, spacing: DS.Space.m) {
                        SectionTitle("Missions")
                        ForEach(Array(stats.enumerated()), id: \.element.id) { i, s in
                            Button { editing = s.mission } label: { missionCard(s) }
                                .buttonStyle(.plain).hoverLift().appear(i)
                        }
                        Text("Marge économique = encaissé HT − frais et commissions − dépenses liées à la mission. Elle ne réduit jamais la base de tes cotisations en micro-entreprise.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                goalCalculator(fin)
            }
            .padding(DS.Space.page)
            .frame(maxWidth: 1100, alignment: .leading)
        }
        .navigationTitle("Missions")
        .toolbar { ToolbarItem { Button { editing = Mission(title: "", clientId: model.ledger.clients.first?.id, dailyRate: model.ledger.profile.defaultDailyRate) } label: { Label("Nouvelle mission", systemImage: "plus") } } }
        .sheet(item: $editing) { MissionEditor(mission: $0) }
    }

    func missionCard(_ s: FinanceEngine.MissionStats) -> some View {
        let m = s.mission
        let progress = m.plannedDays > 0 ? min(NSDecimalNumber(decimal: m.workedDays / m.plannedDays).doubleValue, 1) : 0
        let tint: Color = m.status == .done ? DS.income : (m.status == .active ? DS.brandA : DS.due)
        return Card(tint: tint) {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                HStack(spacing: DS.Space.m) {
                    Avatar(name: model.ledger.client(m.clientId)?.name ?? m.title, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.title).font(.headline).lineLimit(1)
                        Text("\(model.ledger.client(m.clientId)?.name ?? "Sans client") · \(m.dailyRate.formattedShort) / jour").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusTag(text: m.status.label, color: tint, symbol: m.status == .done ? "checkmark" : (m.status == .active ? "play.fill" : "calendar"))
                }
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule().fill(tint.gradient).frame(width: max(progress > 0 ? 8 : 0, g.size.width * progress))
                        }
                    }
                    .frame(height: 8)
                    Text("\(NSDecimalNumber(decimal: m.workedDays)) jours travaillés sur \(NSDecimalNumber(decimal: m.plannedDays)) prévus").font(.caption).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: DS.Space.m)], alignment: .leading, spacing: DS.Space.s) {
                    figure("Facturé HT", s.invoicedHT, nil)
                    figure("Encaissé HT", s.collected, DS.income)
                    figure("Non facturé", s.uninvoicedWork, s.uninvoicedWork.isPositive ? DS.reserve : .secondary)
                    figure("Marge éco.", s.margin, s.margin.isNegative ? DS.outflow : nil)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TJM réel").font(.caption).foregroundStyle(.secondary)
                        Text(s.effectiveDailyRate?.formattedShort ?? "—").font(.body.weight(.semibold)).monospacedDigit()
                    }
                }
            }
        }
    }

    func figure(_ label: String, _ m: Money, _ color: Color?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Amount(money: m, font: .body.weight(.semibold), color: color)
        }
    }

    func goalCalculator(_ fin: FinanceEngine) -> some View {
        let cal = Calendar.fr
        let last3 = Period(start: cal.startOfMonth(cal.date(byAdding: .month, value: -3, to: model.today)!), end: cal.date(byAdding: .day, value: -1, to: cal.startOfMonth(model.today))!)
        let monthlyExp = Money(decimalEuros: fin.expensesPaid(in: last3).0.decimal / 3)
        let need = fin.revenueNeeded(netTarget: goalNet, monthlyExpenses: monthlyExp)
        var days = need.days; var r = Decimal(); NSDecimalRound(&r, &days, 1, .up)
        return Card(tint: DS.brandA) {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                HStack(spacing: DS.Space.s) {
                    IconBubble(symbol: "target", tint: DS.brandA, size: 30, filled: true)
                    Text("Objectif de revenu").font(DS.Font.section)
                    Spacer()
                    Text("Net visé / mois").font(.callout).foregroundStyle(.secondary)
                    MoneyField(title: "Net visé par mois", value: $goalNet).frame(width: 110)
                }
                (Text("Il te faut encaisser ") + Text(need.revenue.description).bold() + Text(" HT par mois, soit ") + Text("\(NSDecimalNumber(decimal: r)) jours").bold() + Text(" à \(need.dailyRate.formattedShort)."))
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Hypothèses : dépenses moyennes des 3 derniers mois (\(monthlyExp)), \(MoneyFormat.percent(1 - fin.netRatio(on: model.today), digits: 1)) de prélèvements estimés d'après ton profil, TJM moyen facturé sur 12 mois.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct MissionEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var mission: Mission
    @State private var hasEnd = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Intitulé", text: $mission.title)
                Picker("Client", selection: $mission.clientId) {
                    Text("Aucun").tag(UUID?.none)
                    ForEach(model.ledger.clients) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                Picker("Statut", selection: $mission.status) { ForEach(MissionStatus.allCases) { Text($0.label).tag($0) } }
                LabeledContent("TJM") { MoneyField(title: "TJM", value: $mission.dailyRate).frame(width: 120) }
                LabeledContent("Jours prévus") { DecimalField(title: "Jours", value: $mission.plannedDays).frame(width: 80) }
                LabeledContent("Jours travaillés") { DecimalField(title: "Jours", value: $mission.workedDays).frame(width: 80) }
                LabeledContent("Frais ou commissions") { MoneyField(title: "Frais", value: $mission.fees).frame(width: 120) }
                DatePicker("Début", selection: $mission.startDate, displayedComponents: .date)
                Toggle("Date de fin prévue", isOn: $hasEnd)
                if hasEnd { DatePicker("Fin", selection: Binding(get: { mission.endDate ?? model.today }, set: { mission.endDate = $0 }), displayedComponents: .date) }
                LabeledContent("Montant prévu") { Amount(money: mission.plannedAmount) }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Enregistrer") {
                    if !hasEnd { mission.endDate = nil }
                    let m = mission
                    model.update("Mission enregistrée.") { l in if let i = l.missions.firstIndex(where: { $0.id == m.id }) { l.missions[i] = m } else { l.missions.append(m) } }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction).disabled(mission.title.isEmpty)
            }.padding(DS.Space.m)
        }
        .frame(width: 440, height: 560)
        .onAppear { hasEnd = mission.endDate != nil }
    }
}
