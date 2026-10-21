import SwiftUI
import CockpitCore
import UniformTypeIdentifiers

struct ExpensesView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: Expense?
    @State private var tab: ExpenseStatus = .paid
    @State private var selection: UUID?

    var body: some View {
        let period = model.period
        let fin = model.finance
        let list: [Expense] = tab == .paid
            ? model.ledger.expenses.filter { $0.status == .paid && period.contains($0.date) }.sorted { $0.date > $1.date }
            : model.ledger.expenses.filter { $0.status == .planned }.sorted { $0.date < $1.date }
        let byCat = Dictionary(grouping: model.ledger.expenses.filter { $0.status == .paid && period.contains($0.date) }, by: \.category)
            .map { ($0.key, $0.value.sum(\.amount)) }.sorted { $0.1 > $1.1 }
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: DS.Space.xxl) {
                VStack(alignment: .leading, spacing: 3) { Text("Payées sur la période").font(.callout).foregroundStyle(.secondary); Amount(money: fin.expensesPaid(in: period).0, font: DS.Font.figureLarge) }
                VStack(alignment: .leading, spacing: 3) { Text("Prévues sur la période").font(.callout).foregroundStyle(.secondary); Amount(money: fin.expensesPlanned(in: period).0, font: DS.Font.figureLarge, color: .secondary) }
                if !byCat.isEmpty {
                    Text(byCat.prefix(3).map { "\($0.0.label) \($0.1.formattedShort)" }.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(DS.Space.l)
            Picker("", selection: $tab) { Text("Payées").tag(ExpenseStatus.paid); Text("Prévues et récurrentes").tag(ExpenseStatus.planned) }
                .pickerStyle(.segmented).labelsHidden().fixedSize().padding(.horizontal, DS.Space.l).padding(.bottom, DS.Space.s)
            if list.isEmpty {
                EmptyState(symbol: "creditcard", title: tab == .paid ? "Aucune dépense payée sur la période" : "Aucune dépense prévue",
                           message: "Saisis une dépense ou importe ton relevé bancaire.", actionTitle: "Nouvelle dépense", action: newExpense)
            } else {
                Table(list, selection: $selection) {
                    TableColumn("Date") { Text($0.date.short) }.width(70)
                    TableColumn("Fournisseur") { e in HStack { IconBubble(symbol: e.category.symbol, tint: e.category.tint, size: 22); Text(e.supplier.isEmpty ? "—" : e.supplier).fontWeight(.medium); if e.attachment != nil { Image(systemName: "paperclip").foregroundStyle(.secondary).help("Justificatif joint") } } }
                    TableColumn("Catégorie") { Text($0.category.label).foregroundStyle(.secondary) }
                    TableColumn("Mission") { Text(model.ledger.mission($0.missionId)?.title ?? "").foregroundStyle(.secondary) }
                    TableColumn("Récurrence") { Text($0.recurrence == .none ? "" : $0.recurrence.label) }.width(90)
                    TableColumn("Montant") { Amount(money: $0.amount).frame(maxWidth: .infinity, alignment: .trailing) }.width(100)
                }
                .contextMenu(forSelectionType: UUID.self) { ids in
                    if let id = ids.first, let e = model.ledger.expenses.first(where: { $0.id == id }) {
                        Button("Modifier…") { editing = e }
                        if e.status == .planned { Button("Marquer payée aujourd'hui") { model.update("Dépense marquée payée.") { $0.markExpensePaid(id: e.id, on: model.today) } } }
                        if let a = e.attachment, let url = model.store?.attachmentURL(a) { Button("Ouvrir le justificatif") { NSWorkspace.shared.open(url) } }
                    }
                } primaryAction: { ids in if let id = ids.first { editing = model.ledger.expenses.first { $0.id == id } } }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Dépenses")
        .toolbar { PeriodToolbar(); ToolbarItem { Button(action: newExpense) { Label("Nouvelle dépense", systemImage: "plus") }.help("Nouvelle dépense (⇧⌘N)") } }
        .sheet(item: $editing) { ExpenseEditor(expense: $0) }
        .task(id: model.pendingNew) { if model.pendingNew == .expenses { model.pendingNew = nil; newExpense() } }
    }

    func newExpense() { editing = Expense(date: model.today, amount: .zero, category: .other, status: tab) }
}

struct ExpenseEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var expense: Expense
    @State private var picking = false
    @State private var confirmDelete = false

    var body: some View {
        let exists = model.ledger.expenses.contains { $0.id == expense.id }
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.m) {
                IconBubble(symbol: expense.category.symbol, tint: expense.category.tint, size: 34, filled: true)
                Text(exists ? "Modifier la dépense" : "Nouvelle dépense").font(.title3.weight(.bold))
                Spacer()
            }
            .padding([.horizontal, .top], DS.Space.l)
            Form {
                LabeledContent("Montant TTC") { MoneyField(title: "Montant", value: $expense.amount).frame(width: 130) }
                if model.ledger.profile.vatRegime == .redevable {
                    LabeledContent("dont TVA déductible") { MoneyField(title: "TVA", value: $expense.vatAmount).frame(width: 130) }
                }
                Picker("Statut", selection: $expense.status) { ForEach(ExpenseStatus.allCases) { Text($0.label).tag($0) } }
                DatePicker(expense.status == .paid ? "Payée le" : "Prévue le", selection: $expense.date, displayedComponents: .date)
                if expense.status == .planned {
                    Picker("Répétition", selection: $expense.recurrence) { ForEach(Recurrence.allCases) { Text($0.label).tag($0) } }
                }
                TextField("Fournisseur", text: $expense.supplier)
                TextField("Description", text: $expense.label)
                Picker("Catégorie", selection: $expense.category) { ForEach(ExpenseCategory.allCases) { Text($0.label).tag($0) } }
                Picker("Mission", selection: $expense.missionId) {
                    Text("Aucune").tag(UUID?.none)
                    ForEach(model.ledger.missions) { Text($0.title).tag(UUID?.some($0.id)) }
                }
                LabeledContent("Justificatif") {
                    HStack {
                        if let a = expense.attachment {
                            Button("Ouvrir") { if let u = model.store?.attachmentURL(a) { NSWorkspace.shared.open(u) } }
                            Button("Retirer") { expense.attachment = nil }.buttonStyle(.borderless)
                        } else {
                            Button("Joindre un PDF ou une image…") { picking = true }
                        }
                    }
                }
                Text("Le justificatif est copié dans le dossier privé de l'app, sur ce Mac uniquement.").font(.caption).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            HStack {
                if exists { Button("Supprimer", role: .destructive) { confirmDelete = true } }
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Enregistrer") {
                    let e = expense
                    model.update("Dépense enregistrée.") { l in if let i = l.expenses.firstIndex(where: { $0.id == e.id }) { l.expenses[i] = e } else { l.expenses.append(e) } }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction).disabled(!expense.amount.isPositive)
            }.padding(DS.Space.m)
        }
        .frame(width: 460, height: 560)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.pdf, .image]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do { expense.attachment = try model.store?.importAttachment(from: url) } catch { model.actionError = error.localizedDescription }
        }
        .confirmationDialog("Supprimer cette dépense ?", isPresented: $confirmDelete) {
            Button("Supprimer", role: .destructive) {
                let id = expense.id
                model.update("Dépense supprimée.") { l in
                    l.expenses.removeAll { $0.id == id }
                    for i in l.transactions.indices where l.transactions[i].linkedExpenseId == id { l.transactions[i].linkedExpenseId = nil }
                }
                dismiss()
            }
        } message: { Text("Cette action est définitive (une sauvegarde automatique quotidienne reste disponible).") }
    }
}

struct ImportView: View {
    @Environment(AppModel.self) private var model
    @State private var picking = false
    @State private var pending: CSVImportResult?
    @State private var matching: BankTransaction?
    @State private var category: ExpenseCategory = .unclassified

    var body: some View {
        let open = model.ledger.transactions.filter { !$0.isLinked }.sorted { $0.date > $1.date }
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Text("Importe un relevé CSV exporté depuis ton espace bancaire. Aucune connexion à ta banque n'est faite : le fichier est lu sur ce Mac.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack { Button("Choisir un fichier CSV…") { picking = true }.buttonStyle(.borderedProminent); Spacer() }
            }
            .padding(DS.Space.l)
            if let p = pending { pendingBanner(p) }
            if open.isEmpty {
                EmptyState(symbol: "tray", title: "Rien à rapprocher", message: model.ledger.transactions.isEmpty ? "Formats reconnus : colonnes Date, Libellé et Montant (ou Débit / Crédit), séparateur ; ou ,." : "Toutes les opérations importées sont classées.")
            } else {
                Table(open) {
                    TableColumn("Date") { Text($0.date.short) }.width(70)
                    TableColumn("Libellé") { Text($0.label) }
                    TableColumn("Montant") { t in Amount(money: t.amount, color: t.amount.isPositive ? DS.income : nil, signed: true).frame(maxWidth: .infinity, alignment: .trailing) }.width(110)
                    TableColumn("Action") { t in
                        HStack {
                            if t.amount.isPositive {
                                Button("Rapprocher d'une facture…") { matching = t }
                            } else {
                                Menu("Créer la dépense") {
                                    ForEach(ExpenseCategory.allCases) { c in Button(c.label) { model.update("Dépense créée.") { try $0.expense(fromTransaction: t.id, category: c) } } }
                                }.fixedSize()
                            }
                            Button("Ignorer") { model.update { l in if let i = l.transactions.firstIndex(where: { $0.id == t.id }) { l.transactions[i].ignored = true } } }.buttonStyle(.borderless)
                        }
                    }.width(300)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Import bancaire")
        .toolbar { ToolbarItem { Button { picking = true } label: { Label("Importer un CSV", systemImage: "square.and.arrow.down") } } }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText, .plainText, UTType(filenameExtension: "csv") ?? .data]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { model.actionError = "Impossible de lire ce fichier."; return }
            let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
            if let r = CSVImporter.parse(text, existing: Set(model.ledger.transactions.map(\.fingerprint))) { pending = r }
            else { model.actionError = "Colonnes non reconnues. Le fichier doit contenir une date, un libellé et un montant (ou débit et crédit)." }
        }
        .sheet(item: $matching) { MatchSheet(transaction: $0) }
    }

    func pendingBanner(_ p: CSVImportResult) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(p.transactions.count) opération\(p.transactions.count > 1 ? "s" : "") à importer").fontWeight(.semibold)
                Text([p.duplicates > 0 ? "\(p.duplicates) déjà importée\(p.duplicates > 1 ? "s" : "") ignorée\(p.duplicates > 1 ? "s" : "")" : nil,
                      p.skippedLines.isEmpty ? nil : "lignes illisibles : \(p.skippedLines.prefix(8).map(String.init).joined(separator: ", "))"].compactMap { $0 }.joined(separator: " · "))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Annuler") { pending = nil }
            Button("Importer") { let txs = p.transactions; model.update("\(txs.count) opérations importées.") { $0.addImported(txs) }; pending = nil }
                .buttonStyle(.borderedProminent).disabled(p.transactions.isEmpty)
        }
        .padding(DS.Space.m)
        .background(DS.due.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.Radius.m))
        .padding(.horizontal, DS.Space.l).padding(.bottom, DS.Space.m)
    }
}

struct MatchSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let transaction: BankTransaction
    var body: some View {
        let candidates = model.finance.openInvoices.sorted { abs($0.balance.cents - transaction.amount.cents) < abs($1.balance.cents - transaction.amount.cents) }
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text("Rapprocher \(transaction.amount) du \(transaction.date.short)").font(.title3.weight(.semibold))
            Text(transaction.label).foregroundStyle(.secondary)
            if candidates.isEmpty { Text("Aucune facture en attente de paiement.").foregroundStyle(.secondary) }
            List(candidates) { inv in
                HStack {
                    VStack(alignment: .leading) { Text(model.finance.clientName(inv)); Text(inv.number ?? "").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Amount(money: inv.balance, color: inv.balance == transaction.amount ? DS.income : nil)
                    Button("Choisir") {
                        if model.update("Paiement enregistré sur \(inv.number ?? "").", { try $0.match(transaction: transaction.id, toInvoice: inv.id) }) { dismiss() }
                    }.disabled(transaction.amount > inv.balance).help(transaction.amount > inv.balance ? "Le montant dépasse le solde restant de cette facture." : "")
                }
            }
            .frame(height: 260)
            HStack { Spacer(); Button("Fermer") { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(DS.Space.l).frame(width: 520)
    }
}
