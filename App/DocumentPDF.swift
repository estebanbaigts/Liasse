import SwiftUI
import PDFKit
import CockpitCore
import UniformTypeIdentifiers

/// Données neutres d'un document imprimable (facture, avoir ou devis).
struct PrintableDocument {
    var title: String
    var number: String?
    var isDraft: Bool
    var issueDate: Date
    var secondaryDateLabel: String
    var secondaryDate: Date
    var issuer: PartySnapshot
    var client: PartySnapshot
    var lines: [DocumentLine]
    var totals: DocumentTotals
    var vatApplicable: Bool
    var paid: Money
    var notes: String
    var paymentTerms: String
    var legalMentions: [String]
    var iban: String
    var bic: String
    var reference: String?

    static func from(invoice inv: Invoice, ledger: Ledger) -> PrintableDocument {
        let issuer = inv.issuerSnapshot ?? .of(profile: ledger.profile)
        let client = inv.clientSnapshot ?? ledger.client(inv.clientId).map(PartySnapshot.of(client:)) ?? PartySnapshot(name: "Client à choisir", address: "", email: "", siret: "", vatNumber: "")
        var ref: String? = nil
        if let q = ledger.quotes.first(where: { $0.id == inv.quoteId })?.number { ref = "Devis \(q)" }
        if let m = ledger.mission(inv.missionId) { ref = [ref, "Mission « \(m.title) »"].compactMap { $0 }.joined(separator: " · ") }
        if let orig = ledger.invoice(inv.correctsInvoiceId)?.number { ref = "Avoir sur la facture \(orig)" }
        let vat = inv.lifecycle == .draft ? ledger.profile.vatRegime == .redevable : inv.vatApplicable
        return PrintableDocument(
            title: inv.kind == .creditNote ? "Avoir" : "Facture", number: inv.number, isDraft: inv.lifecycle == .draft,
            issueDate: inv.issueDate, secondaryDateLabel: inv.kind == .creditNote ? "Date" : "Échéance", secondaryDate: inv.dueDate,
            issuer: issuer, client: client, lines: inv.lines,
            totals: DocumentTotals.compute(lines: inv.lines, discount: inv.discount, vatApplicable: vat), vatApplicable: vat,
            paid: inv.paidAmount, notes: inv.notes,
            paymentTerms: inv.paymentTerms.isEmpty ? "Paiement à \(ledger.profile.paymentTermDays) jours. \(ledger.profile.latePenaltyText)" : inv.paymentTerms,
            legalMentions: inv.lifecycle == .draft ? ledger.profile.legalMentions : inv.legalMentions,
            iban: ledger.profile.iban, bic: ledger.profile.bic, reference: ref)
    }

    static func from(quote q: Quote, ledger: Ledger) -> PrintableDocument {
        let vat = q.number == nil ? ledger.profile.vatRegime == .redevable : q.vatApplicable
        return PrintableDocument(
            title: "Devis", number: q.number, isDraft: q.number == nil, issueDate: q.issueDate,
            secondaryDateLabel: "Valable jusqu'au", secondaryDate: q.validUntil,
            issuer: q.issuerSnapshot ?? .of(profile: ledger.profile),
            client: q.clientSnapshot ?? ledger.client(q.clientId).map(PartySnapshot.of(client:)) ?? PartySnapshot(name: "Client à choisir", address: "", email: "", siret: "", vatNumber: ""),
            lines: q.lines, totals: DocumentTotals.compute(lines: q.lines, discount: q.discount, vatApplicable: vat), vatApplicable: vat,
            paid: .zero, notes: q.notes, paymentTerms: "Devis valable jusqu'au \(q.validUntil.long). Bon pour accord : date et signature du client.",
            legalMentions: q.number == nil ? ledger.profile.legalMentions : q.legalMentions, iban: "", bic: "",
            reference: ledger.mission(q.missionId).map { "Mission « \($0.title) »" })
    }
}

/// Mise en page A4 (595 × 842 pt). Typographie système, une seule couleur d'accent sobre.
struct DocumentPage: View {
    let doc: PrintableDocument
    static let size = CGSize(width: 595, height: 842)
    let ink = Color(white: 0.11), soft = Color(white: 0.42), rule = Color(white: 0.86)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(doc.issuer.name.isEmpty ? "Ton nom" : doc.issuer.name).font(.system(size: 13, weight: .semibold))
                    Text(doc.issuer.address).font(.system(size: 9)).foregroundStyle(soft)
                    if !doc.issuer.email.isEmpty { Text(doc.issuer.email).font(.system(size: 9)).foregroundStyle(soft) }
                    if !doc.issuer.siret.isEmpty { Text("SIRET \(doc.issuer.siret)").font(.system(size: 9)).foregroundStyle(soft) }
                    if !doc.issuer.vatNumber.isEmpty && doc.vatApplicable { Text("TVA \(doc.issuer.vatNumber)").font(.system(size: 9)).foregroundStyle(soft) }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(doc.title).font(.system(size: 24, weight: .semibold))
                    Text(doc.isDraft ? "BROUILLON — non émis" : (doc.number ?? "")).font(.system(size: 10, weight: .medium)).monospacedDigit()
                        .foregroundStyle(doc.isDraft ? Color(red: 0.7, green: 0.25, blue: 0.2) : ink)
                }
            }
            HStack(alignment: .top, spacing: 40) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Facturé à").font(.system(size: 8, weight: .medium)).foregroundStyle(soft)
                    Text(doc.client.name).font(.system(size: 11, weight: .semibold))
                    Text(doc.client.address).font(.system(size: 9)).foregroundStyle(soft)
                    if !doc.client.siret.isEmpty { Text("SIREN \(doc.client.siret)").font(.system(size: 9)).foregroundStyle(soft) }
                    if !doc.client.vatNumber.isEmpty { Text("TVA \(doc.client.vatNumber)").font(.system(size: 9)).foregroundStyle(soft) }
                }
                Spacer()
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 3) {
                    GridRow { Text("Date d'émission").foregroundStyle(soft); Text(doc.issueDate.long) }
                    GridRow { Text(doc.secondaryDateLabel).foregroundStyle(soft); Text(doc.secondaryDate.long) }
                    if let r = doc.reference { GridRow { Text("Référence").foregroundStyle(soft); Text(r).lineLimit(2) } }
                }
                .font(.system(size: 9))
            }
            .padding(.top, 34)

            // Lignes
            VStack(spacing: 0) {
                HStack {
                    Text("Désignation").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Qté").frame(width: 54, alignment: .trailing)
                    Text("Prix unitaire HT").frame(width: 90, alignment: .trailing)
                    if doc.vatApplicable { Text("TVA").frame(width: 40, alignment: .trailing) }
                    Text("Total HT").frame(width: 80, alignment: .trailing)
                }
                .font(.system(size: 8, weight: .medium)).foregroundStyle(soft)
                .padding(.bottom, 6)
                Rectangle().fill(ink).frame(height: 0.8)
                ForEach(doc.lines) { l in
                    HStack(alignment: .firstTextBaseline) {
                        Text(l.label).frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(qty(l.quantity)) \(l.unit.label)\(l.quantity > 1 && l.unit != .flat ? "s" : "")").frame(width: 54, alignment: .trailing)
                        Text(l.unitPrice.description).frame(width: 90, alignment: .trailing)
                        if doc.vatApplicable { Text(MoneyFormat.percent(l.vatRate)).frame(width: 40, alignment: .trailing) }
                        Text(l.totalHT.description).frame(width: 80, alignment: .trailing)
                    }
                    .font(.system(size: 9.5)).monospacedDigit()
                    .padding(.vertical, 7)
                    .overlay(alignment: .bottom) { Rectangle().fill(rule).frame(height: 0.5) }
                }
            }
            .padding(.top, 30)

            // Totaux
            HStack {
                Spacer()
                Grid(alignment: .trailing, horizontalSpacing: 24, verticalSpacing: 4) {
                    if doc.totals.discount.isPositive {
                        GridRow { Text("Sous-total HT").foregroundStyle(soft); Text(doc.totals.grossHT.description) }
                        GridRow { Text("Remise").foregroundStyle(soft); Text((-doc.totals.discount).description) }
                    }
                    GridRow { Text("Total HT").foregroundStyle(soft); Text(doc.totals.netHT.description) }
                    if doc.vatApplicable {
                        ForEach(doc.totals.vatByRate, id: \.rate) { v in
                            GridRow { Text("TVA \(MoneyFormat.percent(v.rate))").foregroundStyle(soft); Text(v.amount.description) }
                        }
                    }
                    GridRow { Text(doc.vatApplicable ? "Total TTC" : "Total").font(.system(size: 11, weight: .semibold)); Text(doc.totals.ttc.description).font(.system(size: 11, weight: .semibold)) }
                    if doc.paid.isPositive {
                        GridRow { Text("Déjà réglé").foregroundStyle(soft); Text((-doc.paid).description) }
                        GridRow { Text("Reste à payer").font(.system(size: 10, weight: .semibold)); Text((doc.totals.ttc - doc.paid).clamped(min: .zero).description).font(.system(size: 10, weight: .semibold)) }
                    }
                }
                .font(.system(size: 9.5)).monospacedDigit()
            }
            .padding(.top, 14)

            if !doc.notes.isEmpty { Text(doc.notes).font(.system(size: 9)).padding(.top, 24) }
            Spacer(minLength: 20)

            VStack(alignment: .leading, spacing: 4) {
                Rectangle().fill(rule).frame(height: 0.5).padding(.bottom, 6)
                Text(doc.paymentTerms).font(.system(size: 8))
                if !doc.iban.isEmpty { Text("Règlement par virement · IBAN \(doc.iban)\(doc.bic.isEmpty ? "" : " · BIC \(doc.bic)")").font(.system(size: 8)).monospacedDigit() }
                if !doc.legalMentions.isEmpty { Text(doc.legalMentions.joined(separator: " · ")).font(.system(size: 8, weight: .medium)) }
            }
            .foregroundStyle(ink)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 48).padding(.top, 50).padding(.bottom, 40)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    func qty(_ d: Decimal) -> String {
        let f = NumberFormatter(); f.locale = Locale(identifier: "fr_FR"); f.maximumFractionDigits = 2
        return f.string(from: NSDecimalNumber(decimal: d)) ?? "\(d)"
    }
}

enum PDFRenderer {
    @MainActor
    static func data(for doc: PrintableDocument) -> Data {
        let renderer = ImageRenderer(content: DocumentPage(doc: doc))
        renderer.proposedSize = .init(DocumentPage.size)
        let data = NSMutableData()
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: DocumentPage.size)
            guard let consumer = CGDataConsumer(data: data as CFMutableData),
                  let ctx = CGContext(consumer: consumer, mediaBox: &box, [kCGPDFContextTitle as String: "\(doc.title) \(doc.number ?? "")",
                                                                           kCGPDFContextCreator as String: "Liasse"] as CFDictionary) else { return }
            ctx.beginPDFPage(nil)
            draw(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
        }
        return data as Data
    }

    static func fileName(for doc: PrintableDocument) -> String {
        "\(doc.title) \(doc.number ?? "brouillon") - \(doc.client.name).pdf".replacingOccurrences(of: "/", with: "-")
    }
}

struct PDFKitView: NSViewRepresentable {
    let data: Data
    func makeNSView(context: Context) -> PDFView {
        let v = PDFView(); v.autoScales = true; v.displayMode = .singlePage; v.backgroundColor = .windowBackgroundColor
        v.document = PDFDocument(data: data); return v
    }
    func updateNSView(_ v: PDFView, context: Context) { v.document = PDFDocument(data: data) }
}

/// Aperçu fidèle : c'est exactement le PDF exporté qui est affiché.
struct PDFPreviewSheet: View {
    let doc: PrintableDocument
    @Environment(\.dismiss) private var dismiss
    @State private var data = Data()
    @State private var exporting = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Aperçu — \(doc.title) \(doc.number ?? "(brouillon)")").font(.headline)
                if doc.isDraft { StatusTag(text: "Brouillon non émis", color: DS.outflow) }
                Spacer()
                Button("Fermer") { dismiss() }
                Button("Exporter le PDF…") { exporting = true }.keyboardShortcut(.defaultAction)
            }
            .padding(DS.Space.m)
            Divider()
            PDFKitView(data: data).frame(minWidth: 620, minHeight: 760)
        }
        .onAppear { data = PDFRenderer.data(for: doc) }
        .fileExporter(isPresented: $exporting, document: PDFFile(data: data), contentType: .pdf, defaultFilename: PDFRenderer.fileName(for: doc)) { _ in }
    }
}

struct PDFFile: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
