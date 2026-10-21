import SwiftUI
import AppKit
import CockpitCore

struct InvoicesView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var editing: Invoice?

    var filtered: [Invoice] {
        let today = model.today
        return model.ledger.invoices.filter { inv in
            let s = inv.status(on: today)
            let ok: Bool = switch model.invoiceFilter {
            case .all: true
            case .unpaid: inv.kind == .invoice && [.issued, .partiallyPaid, .overdue].contains(s)
            case .overdue: s == .overdue
            case .drafts: s == .draft
            case .paid: s == .paid
            }
            guard ok else { return false }
            if search.isEmpty { return true }
            let hay = [inv.number ?? "", model.finance.clientName(inv), inv.lines.map(\.label).joined(separator: " ")].joined(separator: " ")
            return hay.localizedCaseInsensitiveContains(search)
        }.sorted { ($0.lifecycle == .draft ? 1 : 0, $0.issueDate) > ($1.lifecycle == .draft ? 1 : 0, $1.issueDate) }
    }

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Picker("Afficher", selection: $model.invoiceFilter) { ForEach(AppModel.InvoiceFilter.allCases) { Text($0.label).tag($0) } }
                        .pickerStyle(.menu).fixedSize()
                    Spacer()
                    Text("\(filtered.count) document\(filtered.count > 1 ? "s" : "")").font(.caption).foregroundStyle(.secondary)
                }
                .padding(DS.Space.m)
                if filtered.isEmpty {
                    EmptyState(symbol: "doc.text", title: model.ledger.invoices.isEmpty ? "Aucune facture" : "Rien dans ce filtre",
                               message: model.ledger.invoices.isEmpty ? "Crée ta première facture : elle reste un brouillon tant que tu ne l'émets pas." : "Change de filtre pour voir tes autres factures.",
                               actionTitle: model.ledger.invoices.isEmpty ? "Nouvelle facture" : nil, action: newInvoice)
                } else {
                    List(filtered, selection: $model.selectedInvoice) { inv in
                        InvoiceRow(invoice: inv).tag(inv.id)
                    }
                    .listStyle(.inset)
                }
            }
            .frame(width: 320)
            .frame(maxHeight: .infinity, alignment: .top)
            Divider()

            Group {
                if let id = model.selectedInvoice, let inv = model.ledger.invoice(id) {
                    InvoiceDetail(invoice: inv, edit: { editing = $0 })
                } else {
                    EmptyState(symbol: "doc.text.magnifyingglass", title: "Sélectionne une facture", message: "Le détail, les paiements et l'historique s'affichent ici.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Factures")
        .searchable(text: $search, prompt: "Numéro, client, prestation")
        .toolbar { ToolbarItem { Button(action: newInvoice) { Label("Nouvelle facture", systemImage: "plus") }.help("Nouvelle facture (⌘N)") } }
        .sheet(item: $editing) { DocumentEditor(kind: .invoice($0)) }
        .task(id: model.pendingNew) { if model.pendingNew == .invoices { model.pendingNew = nil; newInvoice() } }
    }

    func newInvoice() {
        let p = model.ledger.profile
        var inv = Invoice(clientId: model.ledger.clients.first?.id, issueDate: model.today,
                          dueDate: Calendar.fr.date(byAdding: .day, value: p.paymentTermDays, to: model.today)!)
        inv.lines = [DocumentLine(label: "", quantity: 1, unit: .day, unitPrice: p.defaultDailyRate, vatRate: p.vatRegime == .redevable ? p.vatDefaultRate : 0)]
        editing = inv
    }
}

struct InvoiceRow: View {
    @Environment(AppModel.self) private var model
    let invoice: Invoice
    var body: some View {
        let s = invoice.status(on: model.today)
        HStack(spacing: DS.Space.m) {
            Avatar(name: model.finance.clientName(invoice), size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.finance.clientName(invoice)).fontWeight(.semibold).lineLimit(1)
                Text("\(invoice.kind == .creditNote ? "Avoir " : "")\(invoice.number ?? "Brouillon") · \(invoice.issueDate.short)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Amount(money: invoice.kind == .creditNote ? -invoice.totals.ttc : (s == .partiallyPaid || s == .overdue ? invoice.balance : invoice.totals.ttc))
                StatusTag(text: s == .overdue ? "Retard · \(invoice.daysLate(on: model.today)) j" : s.label, color: s.color, symbol: s.symbol)
            }
        }
        .padding(.vertical, 4)
    }
}

struct InvoiceDetail: View {
    @Environment(AppModel.self) private var model
    let invoice: Invoice
    let edit: (Invoice) -> Void
    @State private var confirmIssue = false
    @State private var confirmCancel = false
    @State private var cancelReason = ""
    @State private var paying = false
    @State private var reminding = false
    @State private var previewing = false
    @State private var confirmDelete = false
    @State private var splitShown: (Payment)? = nil
    @State private var celebrate = 0

    var body: some View {
        let s = invoice.status(on: model.today)
        let t = invoice.totals
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                HStack(alignment: .center, spacing: DS.Space.m) {
                    Avatar(name: model.finance.clientName(invoice), size: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(invoice.kind == .creditNote ? "Avoir" : "Facture") \(invoice.number ?? "brouillon")").font(.title2.weight(.bold))
                        Text(model.finance.clientName(invoice)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusTag(text: s.label, color: s.color, symbol: s.symbol)
                }
                if invoice.kind == .invoice && invoice.lifecycle == .issued {
                    let ratio = t.ttc.isPositive ? NSDecimalNumber(decimal: invoice.paidAmount.decimal / t.ttc.decimal).doubleValue : 0
                    Card(tint: s.color, padding: DS.Space.m + 2) {
                        VStack(alignment: .leading, spacing: DS.Space.s) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(invoice.balance.isZero ? "Tout est réglé" : "Reste à encaisser").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                                Spacer()
                                Amount(money: invoice.balance.isZero ? t.ttc : invoice.balance, font: DS.Font.figureLarge, color: invoice.balance.isZero ? DS.income : nil)
                            }
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.primary.opacity(0.08))
                                    Capsule().fill(DS.income.gradient).frame(width: max(ratio > 0 ? 8 : 0, g.size.width * ratio))
                                }
                            }
                            .frame(height: 10)
                            Text("\(invoice.paidAmount) payés sur \(t.ttc)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .dsAnimation(invoice.paidAmount)
                }
                actions(s)

                Grid(alignment: .leading, horizontalSpacing: DS.Space.xl, verticalSpacing: DS.Space.s) {
                    GridRow { Text("Émission").foregroundStyle(.secondary); Text(invoice.lifecycle == .draft ? "à l'émission" : invoice.issueDate.long) }
                    GridRow { Text("Échéance").foregroundStyle(.secondary); Text(invoice.dueDate.long) }
                    if !(invoice.kind == .invoice && invoice.lifecycle == .issued) {
                        GridRow { Text("Total").foregroundStyle(.secondary); Amount(money: t.ttc) }
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    SectionTitle("Lignes")
                    ForEach(invoice.lines) { l in
                        LedgerRow(title: l.label.isEmpty ? "Sans libellé" : l.label, subtitle: "\(NSDecimalNumber(decimal: l.quantity)) \(l.unit.label) × \(l.unitPrice)", symbol: l.unit == .day ? "calendar" : "shippingbox.fill", tint: DS.brandA) { Amount(money: l.totalHT) }
                    }
                    if t.discount.isPositive { LedgerRow(title: "Remise") { Amount(money: -t.discount) } }
                    if t.vat.isPositive { LedgerRow(title: "TVA") { Amount(money: t.vat) } }
                }

                if invoice.kind == .invoice && invoice.lifecycle != .draft {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionTitle("Paiements")
                        if invoice.payments.isEmpty { Text("Aucun paiement reçu.").foregroundStyle(.secondary).padding(.vertical, 6) }
                        ForEach(invoice.payments) { p in
                            LedgerRow(title: "+\(p.amount.description)", subtitle: "\(p.date.formatted(date: .numeric, time: .omitted)) · \(p.method.label)" + (p.note.isEmpty ? "" : " · \(p.note)"), symbol: "eurosign.circle.fill", tint: DS.income) {
                                Button("Répartition") { splitShown = p }.buttonStyle(.link)
                                Menu { Button("Supprimer ce paiement", role: .destructive) { model.update("Paiement supprimé.") { $0.removePayment(invoiceId: invoice.id, paymentId: p.id, on: model.today) } } } label: { Image(systemName: "ellipsis") }
                                    .menuStyle(.borderlessButton).fixedSize()
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    SectionTitle("Historique")
                    ForEach(invoice.history.reversed()) { h in
                        LedgerRow(title: h.action, subtitle: h.date.formatted(date: .abbreviated, time: .shortened), symbol: "clock.arrow.circlepath", tint: .secondary) { EmptyView() }
                    }
                    if invoice.history.isEmpty { Text("Brouillon créé, jamais émis.").foregroundStyle(.secondary).padding(.vertical, 6) }
                }
            }
            .padding(DS.Space.xl)
        }
        .overlay(alignment: .top) { ConfettiBurst(trigger: celebrate).frame(height: 420) }
        .onChange(of: invoice.balance) { old, new in if old.isPositive && new.isZero && invoice.kind == .invoice { celebrate += 1 } }
        .confirmationDialog("Émettre la facture ?", isPresented: $confirmIssue) {
            Button("Émettre") { model.update("Facture émise.") { try $0.issueInvoice(id: invoice.id, on: model.today) } }
        } message: {
            Text("Elle recevra le numéro suivant de ta séquence et ne pourra plus être modifiée ni supprimée. Pour la corriger, il faudra créer un avoir.")
        }
        .sheet(isPresented: $confirmCancel) { cancelSheet }
        .confirmationDialog("Supprimer ce brouillon ?", isPresented: $confirmDelete) {
            Button("Supprimer", role: .destructive) { model.update("Brouillon supprimé.") { try $0.deleteDraft(id: invoice.id) }; model.selectedInvoice = nil }
        } message: { Text("Un brouillon n'a pas de numéro : le supprimer ne crée aucun trou dans ta séquence.") }
        .sheet(isPresented: $paying) { PaymentSheet(invoice: invoice) }
        .sheet(isPresented: $reminding) { ReminderSheet(invoice: invoice) }
        .sheet(isPresented: $previewing) { PDFPreviewSheet(doc: .from(invoice: invoice, ledger: model.ledger)) }
        .sheet(item: Binding(get: { splitShown.map { SplitBox(payment: $0) } }, set: { splitShown = $0?.payment })) { box in
            SplitSheet(split: model.finance.tax.split(payment: box.payment, invoice: invoice))
        }
    }

    struct SplitBox: Identifiable { var id: UUID { payment.id }; let payment: Payment }

    @ViewBuilder func actions(_ s: InvoiceStatus) -> some View {
        HStack(spacing: DS.Space.s) { actionButtons(s) }.fixedSize()
    }

    @ViewBuilder func actionButtons(_ s: InvoiceStatus) -> some View {
        Group {
            if invoice.lifecycle == .draft {
                Button("Modifier") { edit(invoice) }
                Button("Émettre…") {
                    if let e = model.ledger.issueBlockers(invoice) { model.actionError = e.localizedDescription } else { confirmIssue = true }
                }.buttonStyle(.borderedProminent)
                Button("Aperçu") { previewing = true }
                Button("Supprimer", role: .destructive) { confirmDelete = true }.buttonStyle(.borderless)
            } else {
                if invoice.kind == .invoice && invoice.balance.isPositive && invoice.lifecycle == .issued {
                    Button("Paiement reçu…") { paying = true }.buttonStyle(.borderedProminent).help("Marquer un paiement").fixedSize()
                }
                if s == .overdue || ((s == .issued || s == .partiallyPaid) && invoice.dueDate < Calendar.fr.date(byAdding: .day, value: 3, to: model.today)!) {
                    Button("Relancer…") { reminding = true }.help("Préparer un message de relance").fixedSize()
                }
                Button("PDF") { previewing = true }.help("Aperçu fidèle et export PDF").fixedSize()
                if invoice.kind == .invoice && invoice.lifecycle == .issued {
                    Menu("Plus") { Button("Annuler par un avoir…") { confirmCancel = true } }.menuStyle(.borderlessButton).fixedSize()
                }
            }
        }
    }

    var cancelSheet: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text("Annuler \(invoice.number ?? "")").font(.title3.weight(.semibold))
            Text("Une facture émise ne se supprime pas. Un avoir du montant total sera émis avec son propre numéro ; les paiements déjà reçus restent enregistrés (pense à rembourser le client si besoin).")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("Motif (obligatoire)", text: $cancelReason)
            HStack {
                Spacer()
                Button("Retour") { confirmCancel = false }
                Button("Émettre l'avoir", role: .destructive) {
                    model.update("Avoir émis.") { try $0.cancelInvoice(id: invoice.id, on: model.today, reason: cancelReason) }
                    confirmCancel = false
                }
                .disabled(cancelReason.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DS.Space.l).frame(width: 460)
    }
}

struct PaymentSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let invoice: Invoice
    @State private var amount: Money = .zero
    @State private var date = Date()
    @State private var method: PaymentMethod = .transfer
    @State private var note = ""

    var body: some View {
        let split = model.finance.tax.split(payment: Payment(date: date, amount: amount), invoice: invoice)
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text("Paiement reçu — \(invoice.number ?? "")").font(.title3.weight(.semibold))
            Form {
                LabeledContent("Montant") { MoneyField(title: "Montant", value: $amount).frame(width: 140) }
                Text("Reste dû : \(invoice.balance)").font(.caption).foregroundStyle(amount > invoice.balance ? DS.outflow : .secondary)
                DatePicker("Date de réception", selection: $date, in: ...model.today, displayedComponents: .date)
                Picker("Moyen", selection: $method) { ForEach(PaymentMethod.allCases) { Text($0.label).tag($0) } }
                TextField("Note", text: $note)
            }
            .formStyle(.grouped)
            if amount.isPositive && amount <= invoice.balance {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Répartition indicative").font(.headline)
                    splitRow("Cotisations et CFP", split.cotisations + split.cfp, DS.reserve)
                    if split.incomeTax.isPositive { splitRow(model.ledger.profile.versementLiberatoire ? "Versement libératoire" : "Impôt (estimation)", split.incomeTax, DS.reserve) }
                    if split.vat.isPositive { splitRow("TVA à reverser", split.vat, DS.reserve) }
                    splitRow("Disponible pour toi", split.free, DS.income)
                    if !split.incomeTax.isPositive && !model.ledger.profile.versementLiberatoire {
                        Text("Impôt sur le revenu non estimé : renseigne ton taux de prélèvement à la source dans les réglages.").font(.caption).foregroundStyle(DS.reserve)
                    }
                    Text("Réserves virtuelles : rien ne sort de ton compte tant que tu n'as pas payé l'obligation.").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Annuler") { dismiss() }
                Button("Enregistrer le paiement") {
                    var p = Payment(date: date, amount: amount, method: method); p.note = note
                    if model.update("Paiement de \(amount) enregistré.", { try $0.recordPayment(invoiceId: invoice.id, payment: p) }) { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!amount.isPositive || amount > invoice.balance)
            }
        }
        .padding(DS.Space.l).frame(width: 440)
        .onAppear { amount = invoice.balance; date = model.today }
    }

    func splitRow(_ l: String, _ m: Money, _ c: Color) -> some View {
        HStack { Text(l); Spacer(); Amount(money: m, color: c) }.font(.callout)
    }
}

struct SplitSheet: View {
    let split: ReserveSplit
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text("Répartition de ce paiement").font(.title3.weight(.semibold))
            LedgerRow(title: "Encaissé HT") { Amount(money: split.collectedHT) }
            LedgerRow(title: "Cotisations URSSAF") { Amount(money: split.cotisations, color: DS.reserve) }
            LedgerRow(title: "Formation professionnelle") { Amount(money: split.cfp, color: DS.reserve) }
            LedgerRow(title: "Impôt") { Amount(money: split.incomeTax, color: DS.reserve) }
            if split.vat.isPositive { LedgerRow(title: "TVA") { Amount(money: split.vat, color: DS.reserve) } }
            LedgerRow(title: "Disponible") { Amount(money: split.free, font: .body.weight(.semibold), color: DS.income) }
            Text(split.assumptions.joined(separator: "\n")).font(.caption).foregroundStyle(.secondary).padding(.top, 4)
            HStack { Spacer(); Button("Fermer") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(DS.Space.l).frame(width: 420)
    }
}

/// Relance : le message est préparé, l'envoi reste entièrement entre les mains de l'utilisateur.
struct ReminderSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let invoice: Invoice
    @State private var subject = ""
    @State private var bodyText = ""

    var body: some View {
        let client = model.ledger.client(invoice.clientId)
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text("Relance — \(invoice.number ?? "")").font(.title3.weight(.semibold))
            Text("Relis et ajuste le message. Rien n'est envoyé automatiquement.").foregroundStyle(.secondary)
            TextField("Objet", text: $subject)
            TextEditor(text: $bodyText).font(.body).frame(minHeight: 260).scrollContentBackground(.hidden)
                .padding(6).overlay(RoundedRectangle(cornerRadius: DS.Radius.m).strokeBorder(DS.hairline))
            HStack {
                Button("Copier le message") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("\(subject)\n\n\(bodyText)", forType: .string)
                    markReminded("Message copié.")
                }
                Button("Ouvrir dans Mail") {
                    var c = URLComponents(); c.scheme = "mailto"; c.path = client?.email ?? ""
                    c.queryItems = [URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: bodyText)]
                    if let url = c.url { NSWorkspace.shared.open(url) }
                    markReminded("Brouillon ouvert dans Mail : envoie-le quand tu es prêt.")
                }
                .help(client?.email.isEmpty == false ? "Crée un brouillon adressé à \(client!.email)" : "Ajoute l'e-mail du client pour pré-remplir le destinataire")
                Spacer()
                Button("Fermer") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(DS.Space.l).frame(width: 560)
        .onAppear {
            let m = ReminderComposer.message(for: invoice, profile: model.ledger.profile, contactName: client?.contactName ?? "", today: model.today)
            subject = m.subject; bodyText = m.body
        }
    }

    func markReminded(_ msg: String) {
        model.update(msg) { l in
            guard let i = l.invoices.firstIndex(where: { $0.id == invoice.id }) else { return }
            l.invoices[i].lastReminderDate = model.today
            l.invoices[i].history.append(HistoryEntry(date: Date(), action: "Relance préparée"))
        }
    }
}
