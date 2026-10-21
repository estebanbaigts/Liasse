import Foundation

public enum StoreError: LocalizedError {
    case newerSchema(Int), corrupted(String), backupInvalid(String)
    public var errorDescription: String? {
        switch self {
        case .newerSchema(let v): "Ces données viennent d'une version plus récente de l'app (schéma \(v)). Rien n'a été modifié : mets l'app à jour."
        case .corrupted(let m): "Le fichier de données est illisible (\(m)). Tes sauvegardes automatiques sont intactes : restaure la plus récente depuis Réglages › Données."
        case .backupInvalid(let m): "Cette sauvegarde n'est pas valide (\(m)). Aucune donnée n'a été remplacée."
        }
    }
}

/// Stockage local en JSON, écrit de façon atomique, avec sauvegardes automatiques tournantes.
/// Fichiers en 0600, dossier en 0700 : lisibles uniquement par l'utilisateur.
public final class LedgerStore: @unchecked Sendable {
    public let directory: URL
    public var dataURL: URL { directory.appendingPathComponent("ledger.json") }
    public var backupsURL: URL { directory.appendingPathComponent("Backups", isDirectory: true) }
    public var attachmentsURL: URL { directory.appendingPathComponent("Justificatifs", isDirectory: true) }
    public var maxBackups = 30
    let fm = FileManager.default

    public init(directory: URL) throws {
        self.directory = directory
        for d in [directory, backupsURL, attachmentsURL] {
            try fm.createDirectory(at: d, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
    }

    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Cockpit", isDirectory: true)
    }

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .deferredToDate; return e
    }
    static func decoder() -> JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .deferredToDate; return d }

    public func encode(_ ledger: Ledger) throws -> Data { try Self.encoder().encode(ledger) }

    /// Décode des données en appliquant les migrations de schéma. Ne modifie aucun fichier.
    public static func decode(_ data: Data) throws -> (ledger: Ledger, migratedFrom: Int?) {
        guard var obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw StoreError.corrupted("JSON invalide") }
        let version = obj["schemaVersion"] as? Int ?? 0
        if version > Ledger.currentSchemaVersion { throw StoreError.newerSchema(version) }
        // Chemin direct (précision décimale exacte) quand aucune adaptation n'est nécessaire.
        if version == Ledger.currentSchemaVersion, let l = try? decoder().decode(Ledger.self, from: data) { return (l, nil) }
        var migrated: Int? = nil
        if version < Ledger.currentSchemaVersion { obj = migrate(obj, from: version); migrated = version }
        // Les champs ajoutés au profil après coup reçoivent leur valeur par défaut.
        if let defaults = try? JSONSerialization.jsonObject(with: encoder().encode(BusinessProfile())) as? [String: Any] {
            let stored = obj["profile"] as? [String: Any] ?? [:]
            obj["profile"] = defaults.merging(stored) { _, s in s }
        }
        let fixed = try JSONSerialization.data(withJSONObject: obj)
        do { return (try decoder().decode(Ledger.self, from: fixed), migrated) }
        catch { throw StoreError.corrupted(String(describing: error).prefix(160).description) }
    }

    /// Migrations successives, une étape par version. v0 → v1 : ajout des compteurs et du journal.
    static func migrate(_ input: [String: Any], from version: Int) -> [String: Any] {
        var o = input
        var v = version
        while v < Ledger.currentSchemaVersion {
            switch v {
            case 0:
                if o["counters"] == nil { o["counters"] = [String: Int]() }
                if o["auditLog"] == nil { o["auditLog"] = [Any]() }
                for k in ["clients", "missions", "invoices", "quotes", "expenses", "transactions", "obligationRecords"] where o[k] == nil { o[k] = [Any]() }
            default: break
            }
            v += 1
            o["schemaVersion"] = v
        }
        return o
    }

    /// Charge les données. Si une migration est nécessaire, une sauvegarde de l'original est faite avant.
    public func load() throws -> Ledger {
        guard fm.fileExists(atPath: dataURL.path) else { return Ledger() }
        let data = try Data(contentsOf: dataURL)
        let (ledger, migratedFrom) = try Self.decode(data)
        if let v = migratedFrom {
            try writeBackup(data: data, reason: "avant-migration-v\(v)")
            try save(ledger, backup: false)
        }
        return ledger
    }

    public func save(_ ledger: Ledger, backup: Bool = true) throws {
        let data = try encode(ledger)
        if backup { try backupDailyIfNeeded() }
        try data.write(to: dataURL, options: [.atomic])
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dataURL.path)
    }

    // MARK: Sauvegardes

    public struct BackupInfo: Identifiable, Hashable, Sendable {
        public var id: URL { url }
        public var url: URL
        public var date: Date
        public var size: Int
    }

    public func backups() -> [BackupInfo] {
        let items = (try? fm.contentsOfDirectory(at: backupsURL, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
        return items.filter { $0.pathExtension == "json" }.compactMap { u in
            let v = try? u.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return BackupInfo(url: u, date: v?.contentModificationDate ?? .distantPast, size: v?.fileSize ?? 0)
        }.sorted { $0.date > $1.date }
    }

    func writeBackup(data: Data, reason: String) throws {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd_HH-mm-ss"; f.locale = Locale(identifier: "en_US_POSIX")
        let url = backupsURL.appendingPathComponent("cockpit_\(f.string(from: Date()))_\(reason).json")
        try data.write(to: url, options: [.atomic])
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        prune()
    }

    /// Une sauvegarde automatique par jour, de l'état précédant la première écriture du jour.
    func backupDailyIfNeeded() throws {
        guard fm.fileExists(atPath: dataURL.path) else { return }
        if let last = backups().first, Calendar.fr.isDateInToday(last.date) { return }
        try writeBackup(data: Data(contentsOf: dataURL), reason: "auto")
    }

    @discardableResult
    public func backupNow(_ ledger: Ledger, reason: String = "manuelle") throws -> URL {
        try writeBackup(data: encode(ledger), reason: reason)
        return backups().first!.url
    }

    func prune() {
        let all = backups().filter { !$0.url.lastPathComponent.contains("avant-") }
        for b in all.dropFirst(maxBackups) { try? fm.removeItem(at: b.url) }
    }

    /// Valide une sauvegarde puis remplace les données ; l'état courant est d'abord sauvegardé.
    public func restore(from url: URL) throws -> Ledger {
        let data = try Data(contentsOf: url)
        let ledger: Ledger
        do { ledger = try Self.decode(data).ledger } catch { throw StoreError.backupInvalid(error.localizedDescription) }
        if fm.fileExists(atPath: dataURL.path) { try writeBackup(data: Data(contentsOf: dataURL), reason: "avant-restauration") }
        try save(ledger, backup: false)
        return ledger
    }

    // MARK: Justificatifs

    /// Copie un justificatif dans le dossier privé de l'app et renvoie son nom de fichier.
    public func importAttachment(from source: URL) throws -> String {
        let name = "\(UUID().uuidString).\(source.pathExtension.lowercased())"
        let dest = attachmentsURL.appendingPathComponent(name)
        try fm.copyItem(at: source, to: dest)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dest.path)
        return name
    }

    public func attachmentURL(_ name: String) -> URL { attachmentsURL.appendingPathComponent(name) }
}
