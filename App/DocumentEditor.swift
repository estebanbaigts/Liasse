import SwiftUI
import CockpitCore

/// Éditeur commun aux brouillons de facture et aux devis.
struct DocumentEditor: View {
    enum Kind { case invoice(Invoice), quote(Quote) }
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let kind: Kind

    @State private var clientId: UUID?
    @State private var missionId: UUID?
    @State private var date = Date()
    @State private var secondDate = Date()
    @State private var lines: [DocumentLine] = []
    @State private var discount: Money = .zero
    @State private var notes = ""
    @State private var terms = ""
    @State private var addingClient = false
    @State private var previewing = false

    var isQuote: Bool { if case .quote = kind { true } else { false } }
    var vat: Bool { model.ledger.profile.vatRegime == .redevable }

    var body: some View {
        let totals = DocumentTotals.compute(lines: lines, discount: discount, vatApplicable: vat)
        VStack(spacing: 0) {
            HStack {
                Text(isQuote ? "Devis" : "Facture — brouillon").font(.title3.weight(.semibold))
                Spacer()
                Text("Rien n'est émis ni envoyé depuis cet écran.").font(.callout).foregroundStyle(.secondary)
            }
            .padding(DS.Space.l)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    Form {
                        HStack {
                            Picker("Client", selection: $clientId) {
                                Text("Choisir…").tag(UUID?.none)
                                ForEach(model.ledger.clients) { Text($0.name).tag(UUID?.some($0.id)) }
                            }
                            Button("Nouveau client…") { addingClient = true }
                        }
                        Picker("Mission", selection: $missionId) {
                            Text("Aucune").tag(UUID?.none)
                            ForEach(model.ledger.missions.filter { clientId == nil || $0.clientId == clientId }) { Text($0.title).tag(UUID?.some($0.id)) }
                        }
                        .onChange(of: missionId) { applyMissionRate() }
                        if isQuote {
                            DatePicker("Date", selection: $date, displayedComponents: .date)
                            DatePicker("Valable jusqu'au", selection: $secondDate, in: date..., displayedComponents: .date)
                        } else {
                            DatePicker("Échéance", selection: $secondDate, in: model.today..., displayedComponents: .date)
                            Text("La date d'émission sera celle du jour où tu émettras la facture.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .formStyle(.grouped)
                    .scrollDisabled(true)
                    .frame(height: isQuote ? 220 : 200)

                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        SectionTitle("Prestations")
                        Grid(alignment: .leading, horizontalSpacing: DS.Space.s, verticalSpacing: DS.Space.s) {
                            GridRow {
                                Text("Désignation"); Text("Quantité"); Text("Unité"); Text("Prix unitaire HT")
                                if vat { Text("TVA") }
                                Text("Total HT").gridColumnAlignment(.trailing); Text("")
                            }
                            .font(.caption).foregroundStyle(.secondary)
                            ForEach($lines) { $l in
                                GridRow {
                                    TextField("Description de la prestation", text: $l.label).frame(minWidth: 220)
                                    DecimalField(title: "Qté", value: $l.quantity).frame(width: 64)
                                    Picker("", selection: $l.unit) { ForEach(LineUnit.allCases) { Text($0.label).tag($0) } }.labelsHidden().frame(width: 96)
                                    MoneyField(title: "Prix", value: $l.unitPrice).frame(width: 110)
                                    if vat {
                                        Picker("", selection: $l.vatRate) {
                                            ForEach(["0.2", "0.1", "0.055", "0.021", "0"], id: \.self) { Text(MoneyFormat.percent(Decimal(string: $0)!)).tag(Decimal(string: $0)!) }
                                        }.labelsHidden().frame(width: 80)
                                    }
                                    Amount(money: l.totalHT).frame(minWidth: 96, alignment: .trailing)
                                    Button { lines.removeAll { $0.id == l.id } } label: { Image(systemName: "minus.circle") }
                                        .buttonStyle(.borderless).help("Retirer la ligne").disabled(lines.count == 1)
                                }
                            }
                        }
                        Button { addLine() } label: { Label("Ajouter une ligne", systemImage: "plus") }.buttonStyle(.borderless)
                    }

                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: DS.Space.s) {
                            TextField("Note visible sur le document (référence de commande, période…)", text: $notes, axis: .vertical).lineLimit(2...4)
                            if !isQuote {
                                TextField("Conditions de paiement (vide = conditions par défaut)", text: $terms, axis: .vertical).lineLimit(2...4)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        Spacer(minLength: DS.Space.xl)
                        Grid(alignment: .trailing, horizontalSpacing: DS.Space.l, verticalSpacing: 6) {
                            GridRow { Text("Remise HT").foregroundStyle(.secondary); MoneyField(title: "Remise", value: $discount).frame(width: 110) }
                            GridRow { Text("Total HT").foregroundStyle(.secondary); Amount(money: totals.netHT) }
                            if vat { GridRow { Text("TVA").foregroundStyle(.secondary); Amount(money: totals.vat) } }
                            GridRow { Text(vat ? "Total TTC" : "Total").fontWeight(.semibold); Amount(money: totals.ttc, font: DS.Font.figure) }
                        }
                    }
                    if !vat { Text("Mention ajoutée automatiquement : « TVA non applicable, art. 293 B du CGI ».").font(.caption).foregroundStyle(.secondary) }
                }
                .padding(DS.Space.l)
            }
            Divider()
            HStack {
                Button("Aperçu") { previewing = true }
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isQuote ? "Enregistrer le devis" : "Enregistrer le brouillon") { save() }.keyboardShortcut(.defaultAction)
            }
            .padding(DS.Space.m)
        }
        .frame(width: 860, height: 700)
        .onAppear(perform: load)
        .sheet(isPresented: $addingClient) { ClientEditor(client: Client(name: "")) { c in clientId = c.id } }
        .sheet(isPresented: $previewing) { PDFPreviewSheet(doc: previewDoc()) }
    }

    func load() {
        switch kind {
        case .invoice(let i): clientId = i.clientId; missionId = i.missionId; date = i.issueDate; secondDate = i.dueDate; lines = i.lines; discount = i.discount; notes = i.notes; terms = i.paymentTerms
        case .quote(let q): clientId = q.clientId; missionId = q.missionId; date = q.issueDate; secondDate = q.validUntil; lines = q.lines; discount = q.discount; notes = q.notes
        }
        if lines.isEmpty { addLine() }
    }

    func addLine() {
        let p = model.ledger.profile
        lines.append(DocumentLine(label: "", quantity: 1, unit: .day, unitPrice: model.ledger.mission(missionId)?.dailyRate ?? p.defaultDailyRate, vatRate: vat ? p.vatDefaultRate : 0))
    }

    func applyMissionRate() {
        guard let m = model.ledger.mission(missionId) else { return }
        for i in lines.indices where lines[i].unit == .day && lines[i].label.isEmpty { lines[i].unitPrice = m.dailyRate; lines[i].label = m.title }
    }

    func cleanedLines() -> [DocumentLine] { lines.filter { !$0.label.trimmingCharacters(in: .whitespaces).isEmpty || $0.unitPrice.isPositive } }

    func previewDoc() -> PrintableDocument {
        switch kind {
        case .invoice(var i): i.clientId = clientId; i.missionId = missionId; i.dueDate = secondDate; i.lines = cleanedLines(); i.discount = discount; i.notes = notes; i.paymentTerms = terms
            if i.lifecycle == .draft { i.issueDate = model.today }
            return .from(invoice: i, ledger: model.ledger)
        case .quote(var q): q.clientId = clientId; q.missionId = missionId; q.issueDate = date; q.validUntil = secondDate; q.lines = cleanedLines(); q.discount = discount; q.notes = notes
            return .from(quote: q, ledger: model.ledger)
        }
    }

    func save() {
        let ls = cleanedLines()
        switch kind {
        case .invoice(var i):
            guard i.lifecycle == .draft else { model.actionError = LedgerError.invoiceNotDraft.localizedDescription; return }
            i.clientId = clientId; i.missionId = missionId; i.dueDate = secondDate; i.lines = ls; i.discount = discount; i.notes = notes; i.paymentTerms = terms
            model.update("Brouillon enregistré. Il n'est pas encore émis.") { l in
                if let idx = l.invoices.firstIndex(where: { $0.id == i.id }) { l.invoices[idx] = i } else { l.invoices.append(i) }
            }
            model.selectedInvoice = i.id
        case .quote(var q):
            q.clientId = clientId; q.missionId = missionId; q.issueDate = date; q.validUntil = secondDate; q.lines = ls; q.discount = discount; q.notes = notes
            model.update("Devis enregistré.") { l in
                if let idx = l.quotes.firstIndex(where: { $0.id == q.id }) { l.quotes[idx] = q } else { l.quotes.append(q) }
            }
        }
        dismiss()
    }
}

struct QuotesView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: Quote?
    @State private var preview: Quote?
    @State private var selection: UUID?

    var body: some View {
        let quotes = model.ledger.quotes.sorted { $0.issueDate > $1.issueDate }
        Group {
            if quotes.isEmpty {
                EmptyState(symbol: "doc.plaintext", title: "Aucun devis", message: "Un devis accepté se convertit en facture en un clic.", actionTitle: "Nouveau devis", action: newQuote)
            } else {
                Table(quotes, selection: $selection) {
                    TableColumn("Numéro") { Text($0.number ?? "Brouillon").monospacedDigit() }.width(110)
                    TableColumn("Client") { Text(model.ledger.client($0.clientId)?.name ?? "—") }
                    TableColumn("Date") { Text($0.issueDate.short) }.width(80)
                    TableColumn("Validité") { q in Text(q.validUntil.short).foregroundStyle(q.validUntil < model.today && q.status == .sent ? DS.outflow : .primary) }.width(80)
                    TableColumn("Montant") { Amount(money: $0.totals.ttc).frame(maxWidth: .infinity, alignment: .trailing) }.width(110)
                    TableColumn("Statut") { q in StatusTag(text: q.status.label, color: q.status == .accepted ? DS.income : (q.status == .refused ? DS.outflow : (q.status == .invoiced ? .secondary : DS.due))) }.width(100)
                }
                .contextMenu(forSelectionType: UUID.self) { ids in
                    if let id = ids.first, let q = model.ledger.quotes.first(where: { $0.id == id }) { menu(q) }
                } primaryAction: { ids in
                    if let id = ids.first, let q = model.ledger.quotes.first(where: { $0.id == id }) { if q.number == nil { editing = q } else { preview = q } }
                }
            }
        }
        .navigationTitle("Devis")
        .toolbar {
            if let id = selection, let q = model.ledger.quotes.first(where: { $0.id == id }) {
                ToolbarItemGroup { menuButtons(q) }
            }
            ToolbarItem { Button(action: newQuote) { Label("Nouveau devis", systemImage: "plus") } }
        }
        .sheet(item: $editing) { DocumentEditor(kind: .quote($0)) }
        .sheet(item: $preview) { PDFPreviewSheet(doc: .from(quote: $0, ledger: model.ledger)) }
    }

    @ViewBuilder func menuButtons(_ q: Quote) -> some View {
        if q.number == nil {
            Button("Modifier") { editing = q }
            Button("Finaliser") { model.update("Devis \(q.clientId == nil ? "" : "finalisé et numéroté").") { try $0.finalizeQuote(id: q.id, on: model.today) } }
        } else if q.status == .sent {
            Button("Accepté") { setStatus(q, .accepted) }
            Button("Refusé") { setStatus(q, .refused) }
        } else if q.status == .accepted {
            Button("Convertir en facture") {
                var newId: UUID?
                if model.update("Facture brouillon créée depuis le devis.", { newId = try $0.convertQuote(id: q.id, on: model.today).id }) {
                    model.selectedInvoice = newId; model.invoiceFilter = .all; model.screen = .invoices
                }
            }
        }
        Button("Aperçu et PDF") { preview = q }
    }

    @ViewBuilder func menu(_ q: Quote) -> some View { menuButtons(q) }

    func setStatus(_ q: Quote, _ s: QuoteStatus) {
        model.update("Devis marqué « \(s.label.lowercased()) ».") { l in
            guard let i = l.quotes.firstIndex(where: { $0.id == q.id }) else { return }
            l.quotes[i].status = s
            l.quotes[i].history.append(HistoryEntry(date: model.today, action: "Marqué \(s.label.lowercased())"))
        }
    }

    func newQuote() {
        var q = Quote(clientId: model.ledger.clients.first?.id, issueDate: model.today, validUntil: Calendar.fr.date(byAdding: .day, value: 30, to: model.today)!)
        q.lines = []
        editing = q
    }
}
