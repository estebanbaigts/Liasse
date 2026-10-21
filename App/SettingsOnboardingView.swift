import SwiftUI
import CockpitCore
import UniformTypeIdentifiers

/// Sections de profil réutilisées par l'assistant et les réglages.
struct ProfileFiscalSection: View {
    @Binding var p: BusinessProfile
    var body: some View {
        Section("Statut") {
            Picker("Forme juridique", selection: $p.legalForm) { ForEach(LegalForm.allCases) { Text($0.label).tag($0) } }
            if !p.legalForm.isAutomaticallySupported {
                Text("Seule la micro-entreprise est calculée automatiquement. Pour ce statut, les cotisations et impôts dépendent de ta rémunération et de ton régime : fais-les établir par un expert-comptable.")
                    .font(.caption).foregroundStyle(DS.reserve)
            }
            Picker("Activité", selection: $p.activity) { ForEach(ActivityCategory.allCases) { Text($0.label).tag($0) } }
            if p.activity != .liberaleSSI && p.activity != .liberaleCipav { Toggle("Activité artisanale (immatriculée au registre des métiers)", isOn: $p.isArtisan) }
            DatePicker("Début d'activité", selection: $p.activityStart, displayedComponents: .date)
        }
    }
}

struct ProfileRegimeSection: View {
    @Binding var p: BusinessProfile
    @State private var hasPAS = false
    @State private var hasCFE = false
    @State private var hasOverride = false
    var body: some View {
        Section("URSSAF") {
            Picker("Déclaration du chiffre d'affaires", selection: $p.urssafPeriodicity) { ForEach(DeclarationPeriodicity.allCases) { Text($0.label).tag($0) } }
            Toggle("Versement libératoire de l'impôt", isOn: $p.versementLiberatoire)
            if p.versementLiberatoire { Text("Possible seulement si ton revenu fiscal de référence N-2 est sous le plafond (29 579 € pour une personne seule en 2026).").font(.caption).foregroundStyle(.secondary) }
            Toggle("Je bénéficie de l'ACRE", isOn: $p.acre)
            Toggle("Utiliser le taux exact indiqué par l'URSSAF", isOn: $hasOverride)
                .onChange(of: hasOverride) { if !hasOverride { p.cotisationRateOverride = nil } else if p.cotisationRateOverride == nil { p.cotisationRateOverride = Decimal(string: "0.128") } }
            if hasOverride {
                LabeledContent("Taux de cotisations (%)") { DecimalField(title: "%", value: Binding(get: { p.cotisationRateOverride ?? 0 }, set: { p.cotisationRateOverride = $0 }), percent: true).frame(width: 80) }
                Text("Prioritaire sur le catalogue de règles (utile avec l'ACRE).").font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { hasOverride = p.cotisationRateOverride != nil; hasPAS = p.withholdingTaxRate != nil; hasCFE = p.cfeAmount != nil }
        Section("TVA") {
            Picker("Situation", selection: $p.vatRegime) { ForEach(VATRegime.allCases) { Text($0.label).tag($0) } }
            if p.vatRegime == .redevable {
                LabeledContent("Taux par défaut (%)") { DecimalField(title: "%", value: $p.vatDefaultRate, percent: true).frame(width: 80) }
                Picker("Déclaration de TVA", selection: $p.vatPeriodicity) { ForEach(DeclarationPeriodicity.allCases) { Text($0.label).tag($0) } }
            }
        }
        Section("Impôt et CFE") {
            if !p.versementLiberatoire {
                Toggle("Je connais mon taux de prélèvement à la source", isOn: $hasPAS)
                    .onChange(of: hasPAS) { if !hasPAS { p.withholdingTaxRate = nil } else if p.withholdingTaxRate == nil { p.withholdingTaxRate = Decimal(string: "0.075") } }
                if hasPAS { LabeledContent("Taux (%)") { DecimalField(title: "%", value: Binding(get: { p.withholdingTaxRate ?? 0 }, set: { p.withholdingTaxRate = $0 }), percent: true).frame(width: 80) } }
                Text("Il figure sur impots.gouv.fr › Gérer mon prélèvement à la source. Sans lui, l'impôt n'est pas estimé.").font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Je connais le montant de ma CFE", isOn: $hasCFE)
                .onChange(of: hasCFE) { if !hasCFE { p.cfeAmount = nil } else if p.cfeAmount == nil { p.cfeAmount = .zero } }
            if hasCFE { LabeledContent("CFE annuelle") { MoneyField(title: "CFE", value: Binding(get: { p.cfeAmount ?? .zero }, set: { p.cfeAmount = $0 })).frame(width: 120) } }
        }
    }
}

struct ProfileIdentitySection: View {
    @Binding var p: BusinessProfile
    var body: some View {
        Section("Émetteur des factures") {
            TextField("Nom et prénom", text: $p.ownerName)
            TextField("Nom commercial (facultatif)", text: $p.tradeName)
            TextField("Adresse", text: $p.address, axis: .vertical).lineLimit(2...4)
            TextField("SIRET (14 chiffres)", text: $p.siret)
            if !p.siret.isEmpty && p.siret.filter(\.isNumber).count != 14 { Text("Le SIRET doit comporter 14 chiffres.").font(.caption).foregroundStyle(DS.outflow) }
            TextField("E-mail", text: $p.email)
            TextField("Téléphone", text: $p.phone)
            if p.vatRegime == .redevable { TextField("N° de TVA intracommunautaire", text: $p.vatNumber) }
            TextField("IBAN (affiché sur tes factures)", text: $p.iban)
            TextField("BIC", text: $p.bic)
        }
        Section("Conditions de paiement") {
            Stepper("Échéance par défaut : \(p.paymentTermDays) jours", value: $p.paymentTermDays, in: 0...60, step: 5)
            TextField("Pénalités de retard", text: $p.latePenaltyText, axis: .vertical).lineLimit(2...4)
        }
    }
}

struct ProfilePilotSection: View {
    @Binding var p: BusinessProfile
    var body: some View {
        Section("Trésorerie et objectifs") {
            LabeledContent("Solde du compte pro") { MoneyField(title: "Solde", value: $p.openingBalance).frame(width: 130) }
            DatePicker("au matin du", selection: $p.openingBalanceDate, displayedComponents: .date)
            Text("Point de départ du solde reconstitué. Mets-le à jour avec ton relevé quand tu veux recaler.").font(.caption).foregroundStyle(.secondary)
            LabeledContent("Objectif de CA mensuel HT") { MoneyField(title: "Objectif", value: $p.monthlyRevenueGoal).frame(width: 130) }
            LabeledContent("TJM par défaut") { MoneyField(title: "TJM", value: $p.defaultDailyRate).frame(width: 130) }
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var tab = 0
    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) { Text("Profil").tag(0); Text("Règles fiscales").tag(1); Text("Données").tag(2); Text("Confidentialité").tag(3) }
                .pickerStyle(.segmented).labelsHidden().fixedSize().padding(DS.Space.m)
            switch tab {
            case 0: ProfileSettings()
            case 1: RulesSettings()
            case 2: DataSettings()
            default: PrivacySettings()
            }
        }
        .navigationTitle("Réglages")
    }
}

struct ProfileSettings: View {
    @Environment(AppModel.self) private var model
    @State private var p = BusinessProfile()
    @State private var loaded = false
    var body: some View {
        Form {
            ProfileFiscalSection(p: $p)
            ProfileRegimeSection(p: $p)
            ProfileIdentitySection(p: $p)
            ProfilePilotSection(p: $p)
        }
        .formStyle(.grouped)
        .onAppear { p = model.ledger.profile; loaded = true }
        .onChange(of: p) { if loaded && p != model.ledger.profile { let v = p; model.update { $0.profile = v } } }
    }
}

struct RulesSettings: View {
    @Environment(AppModel.self) private var model
    @State private var editing: TaxRule?
    @State private var confirmReset = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Chaque calcul utilise ces règles. Elles sont datées, sourcées et modifiables ; une modification demande confirmation.").foregroundStyle(.secondary)
                Spacer()
                Button("Rétablir le catalogue vérifié…") { confirmReset = true }
            }
            .padding(.horizontal, DS.Space.l).padding(.bottom, DS.Space.s)
            Table(model.ledger.rules.rules) {
                TableColumn("Règle") { r in VStack(alignment: .leading) { Text(r.key.label); Text(r.activities.map(\.label).joined(separator: ", ").ifEmptyText("Toutes activités")).font(.caption).foregroundStyle(.secondary).lineLimit(2) } }.width(min: 220, ideal: 300)
                TableColumn("Valeur") { r in Text(r.formattedValue).monospacedDigit() }.width(90)
                TableColumn("Depuis") { Text($0.effectiveFrom.formatted(date: .numeric, time: .omitted)) }.width(80)
                TableColumn("Vérifiée") { r in HStack { Text(r.verifiedOn.formatted(date: .numeric, time: .omitted)); if r.confidence == .toVerify { StatusTag(text: "à vérifier", color: DS.reserve) }; if r.userModified { StatusTag(text: "modifiée", color: DS.due) } } }.width(170)
                TableColumn("Source") { r in if let u = URL(string: r.sourceURL) { Link(u.lastPathComponent, destination: u) } }.width(70)
                TableColumn("") { r in Button("Modifier…") { editing = r }.buttonStyle(.borderless) }.width(80)
            }
        }
        .sheet(item: $editing) { RuleEditor(rule: $0) }
        .confirmationDialog("Rétablir le catalogue vérifié ?", isPresented: $confirmReset) {
            Button("Rétablir", role: .destructive) { model.update("Catalogue rétabli.") { $0.rules = .defaultCatalogue } }
        } message: { Text("Tes modifications de règles seront remplacées par les valeurs vérifiées le 21 octobre 2026.") }
    }
}

extension String { func ifEmptyText(_ s: String) -> String { isEmpty ? s : self } }

struct RuleEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var rule: TaxRule
    @State private var confirm = false
    @State private var asNewVersion = true
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text(rule.key.label).font(.title3.weight(.semibold))
            Text(rule.note).font(.caption).foregroundStyle(.secondary)
            Form {
                LabeledContent(rule.nature == .threshold ? "Valeur (€)" : "Valeur (%)") {
                    DecimalField(title: "Valeur", value: $rule.value, percent: rule.nature != .threshold).frame(width: 100)
                }
                Toggle("Créer une nouvelle version (garde l'ancienne pour les périodes passées)", isOn: $asNewVersion)
                DatePicker("Prend effet le", selection: $rule.effectiveFrom, displayedComponents: .date)
                TextField("Source (URL officielle)", text: $rule.sourceURL)
                Picker("Fiabilité", selection: $rule.confidence) { ForEach(RuleConfidence.allCases, id: \.self) { Text($0.label).tag($0) } }
                TextField("Note", text: $rule.note, axis: .vertical)
            }
            .formStyle(.grouped).frame(height: 300)
            HStack { Spacer(); Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction); Button("Enregistrer…") { confirm = true }.keyboardShortcut(.defaultAction) }
        }
        .padding(DS.Space.l).frame(width: 520)
        .confirmationDialog("Modifier cette règle fiscale ?", isPresented: $confirm) {
            Button("Confirmer la modification") {
                var r = rule; r.userModified = true; r.verifiedOn = model.today
                let original = rule.id
                model.update("Règle modifiée : les estimations sont recalculées.") { l in
                    if asNewVersion {
                        r.id = "\(original)-u\(Int(Date().timeIntervalSince1970))"
                        if let i = l.rules.rules.firstIndex(where: { $0.id == original }) {
                            l.rules.rules[i].effectiveTo = Calendar.fr.date(byAdding: .day, value: -1, to: r.effectiveFrom)
                        }
                        l.rules.rules.append(r)
                    } else if let i = l.rules.rules.firstIndex(where: { $0.id == original }) { l.rules.rules[i] = r }
                    l.auditLog.append(HistoryEntry(action: "Règle \(r.key.label) → \(r.formattedValue)"))
                }
                dismiss()
            }
        } message: { Text("Toutes les estimations qui utilisent cette règle seront recalculées. Vérifie la valeur sur une source officielle.") }
    }
}

struct DataSettings: View {
    @Environment(AppModel.self) private var model
    @State private var restoreTarget: URL?
    @State private var importing = false
    @State private var exporting = false
    @State private var confirmReset = false
    @State private var confirmSample = false

    var body: some View {
        Form {
            Section("Emplacement") {
                LabeledContent("Dossier des données") { Text(model.store?.directory.path ?? "—").font(.caption).textSelection(.enabled).lineLimit(2) }
                Button("Afficher dans le Finder") { if let d = model.store?.directory { NSWorkspace.shared.activateFileViewerSelecting([d]) } }
                if let s = model.lastSaved { Text("Dernier enregistrement : \(s.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
            }
            Section("Sauvegardes") {
                Text("Une sauvegarde automatique par jour (30 conservées), plus une avant chaque migration ou restauration.").font(.caption).foregroundStyle(.secondary)
                HStack { Button("Sauvegarder maintenant") { model.backupNow() }; Button("Exporter une sauvegarde…") { exporting = true }; Button("Restaurer depuis un fichier…") { importing = true } }
                ForEach(model.store?.backups().prefix(8) ?? []) { b in
                    HStack {
                        Text(b.date.formatted(date: .abbreviated, time: .shortened))
                        Text(b.url.lastPathComponent.contains("avant-") ? "avant opération" : "").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: Int64(b.size), countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                        Button("Restaurer…") { restoreTarget = b.url }
                    }
                }
            }
            Section("Widget") {
                if model.widgetSharingAvailable {
                    Label("Le widget reçoit un résumé à chaque modification.", systemImage: "checkmark.circle").foregroundStyle(DS.income)
                } else {
                    Label("Partage avec le widget indisponible : l'app doit être signée avec une équipe de développement Apple (App Group). Voir le README.", systemImage: "exclamationmark.triangle").foregroundStyle(DS.reserve)
                }
            }
            Section("Aperçu du widget") {
                WidgetPreviewGallery()
            }
            Section("Rappels") {
                Button("Programmer des rappels 5 jours avant chaque échéance") { Task { await model.scheduleDeadlineNotifications() } }
                Text("Notifications locales uniquement, sans montant dans le texte.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Réinitialiser") {
                Button("Charger des données d'exemple…") { confirmSample = true }
                Button("Effacer toutes les données…", role: .destructive) { confirmReset = true }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Restaurer cette sauvegarde ?", isPresented: Binding(get: { restoreTarget != nil }, set: { if !$0 { restoreTarget = nil } })) {
            Button("Restaurer", role: .destructive) { if let u = restoreTarget { model.restore(from: u) } }
        } message: { Text("Tes données actuelles seront d'abord sauvegardées, puis remplacées.") }
        .confirmationDialog("Effacer toutes les données ?", isPresented: $confirmReset) {
            Button("Tout effacer", role: .destructive) { model.resetAll() }
        } message: { Text("Une sauvegarde est faite juste avant : tu pourras revenir en arrière depuis cette page.") }
        .confirmationDialog("Remplacer tes données par des données d'exemple ?", isPresented: $confirmSample) {
            Button("Charger l'exemple", role: .destructive) { model.backupNow(); model.loadSample() }
        } message: { Text("Tes données actuelles sont sauvegardées d'abord. Les exemples sont fictifs.") }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { r in
            if case .success(let url) = r {
                let a = url.startAccessingSecurityScopedResource(); defer { if a { url.stopAccessingSecurityScopedResource() } }
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
                try? FileManager.default.copyItem(at: url, to: tmp)
                restoreTarget = tmp
            }
        }
        .fileExporter(isPresented: $exporting, document: JSONFile(data: (try? model.store?.encode(model.ledger)) ?? Data()), contentType: .json,
                      defaultFilename: "Liasse-sauvegarde-\(Date().formatted(.iso8601.year().month().day())).json") { _ in }
    }
}

struct JSONFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct PrivacySettings: View {
    var body: some View {
        Form {
            Section("Ce que fait Liasse de tes données") {
                Label("Tout est stocké sur ce Mac, dans le dossier privé de l'app (fichiers lisibles par toi seul).", systemImage: "internaldrive")
                Label("Aucune télémétrie, aucun traçage, aucun compte, aucune synchronisation cloud.", systemImage: "eye.slash")
                Label("Aucune connexion bancaire : les relevés sont importés depuis un fichier que tu choisis.", systemImage: "building.columns")
                Label("Aucune IA externe : les recommandations sont calculées localement par des règles déterministes.", systemImage: "cpu")
                Label("Rien n'est envoyé sans toi : les relances s'ouvrent en brouillon, tu les envoies toi-même.", systemImage: "envelope")
                Label("Seuls les liens vers les sources officielles ouvrent ton navigateur, quand tu cliques dessus.", systemImage: "link")
            }
            Section("Protéger tes données") {
                Text("Active FileVault (Réglages Système › Confidentialité et sécurité) pour chiffrer le disque, et range tes sauvegardes exportées dans un endroit sûr : elles contiennent tes données financières en clair.")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Assistant de configuration

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var p = BusinessProfile()
    let titles = ["Bienvenue", "Ton statut", "Tes déclarations", "Tes coordonnées", "Ta trésorerie"]
    let symbols = ["hand.wave.fill", "person.text.rectangle.fill", "doc.badge.clock.fill", "envelope.fill", "banknote.fill"]
    let tints = [DS.brandA, DS.brandB, DS.reserve, DS.due, DS.income]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.m) {
                IconBubble(symbol: symbols[step], tint: tints[step], size: 44, filled: true)
                    .symbolEffect(.bounce, value: step)
                Text(titles[step]).font(.title2.weight(.bold))
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0..<titles.count, id: \.self) { i in
                        Capsule().fill(i <= step ? AnyShapeStyle(DS.brand) : AnyShapeStyle(Color.primary.opacity(0.12)))
                            .frame(width: i == step ? 22 : 8, height: 8)
                    }
                }
                .accessibilityLabel("Étape \(step + 1) sur \(titles.count)")
            }
            .padding(DS.Space.l)
            .dsAnimation(step)
            Divider()
            Group {
                switch step {
                case 0:
                    VStack(alignment: .leading, spacing: DS.Space.m) {
                        Text("Liasse t'aide à savoir combien tu as vraiment gagné, combien tu peux utiliser et combien garder pour l'URSSAF et les impôts.")
                            .font(.title3).fixedSize(horizontal: false, vertical: true)
                        Text("Quelques questions pour calculer selon ta situation réelle : aucun taux n'est supposé à ta place. Tu pourras tout modifier dans les réglages.")
                            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Label("Tes données restent sur ce Mac. Aucun compte, aucun cloud, aucune connexion bancaire.", systemImage: "lock")
                        Spacer()
                        Button("Explorer d'abord avec des données d'exemple") { model.loadSample(); dismiss() }.buttonStyle(.link)
                    }
                    .padding(DS.Space.xl)
                case 1: Form { ProfileFiscalSection(p: $p) }.formStyle(.grouped)
                case 2: Form { ProfileRegimeSection(p: $p) }.formStyle(.grouped)
                case 3: Form { ProfileIdentitySection(p: $p) }.formStyle(.grouped)
                default: Form { ProfilePilotSection(p: $p) }.formStyle(.grouped)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            HStack {
                if step > 0 { Button("Retour") { step -= 1 } }
                Spacer()
                if step == 3 { Text("Tu pourras compléter plus tard : ces informations sont exigées avant d'émettre une facture.").font(.caption).foregroundStyle(.secondary) }
                if step < titles.count - 1 {
                    Button("Continuer") { step += 1 }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Terminer") {
                        var v = p; v.onboardingCompleted = true
                        model.update("Profil enregistré.") { $0.profile = v }
                        dismiss()
                    }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(DS.Space.m)
        }
        .frame(width: 620, height: 600)
        .fontDesign(.rounded)
        .interactiveDismissDisabled()
        .onAppear { p = model.ledger.profile }
    }
}


/// Aperçu fidèle des trois tailles du widget, calculé avec les mêmes données que celles envoyées au widget.
struct WidgetPreviewGallery: View {
    @Environment(AppModel.self) private var model
    @State private var hide = false
    var body: some View {
        let snap = WidgetSnapshot.make(from: model.ledger, today: model.today)
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Toggle("Masquer les montants", isOn: $hide)
            HStack(alignment: .top, spacing: DS.Space.l) {
                tile(.small, CGSize(width: 170, height: 170), snap)
                tile(.medium, CGSize(width: 364, height: 170), snap)
            }
            tile(.large, CGSize(width: 364, height: 382), snap)
        }
    }
    func tile(_ size: WidgetSize, _ dim: CGSize, _ s: WidgetSnapshot) -> some View {
        CockpitWidgetContent(size: size, snapshot: s, hide: hide, showTrend: true)
            .padding(16)
            .frame(width: dim.width, height: dim.height)
            .fontDesign(.rounded)
            .background(LinearGradient(colors: [DS.brandA.opacity(0.18), DS.income.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(DS.hairline))
    }
}
