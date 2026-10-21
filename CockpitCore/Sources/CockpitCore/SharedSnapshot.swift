import Foundation

/// Échange de l'instantané entre l'app et le widget via le conteneur App Group.
/// L'identifiant vient d'une seule clé Info.plist (`CockpitAppGroup`, réglage de build `COCKPIT_APP_GROUP`).
/// Sans équipe de développement, le conteneur n'existe pas : le widget affiche alors un état explicite.
public enum SharedSnapshot {
    public static var appGroup: String? {
        guard let g = Bundle.main.object(forInfoDictionaryKey: "CockpitAppGroup") as? String,
              !g.isEmpty, !g.contains("$(") else { return nil }
        return g
    }

    public static var fileURL: URL? {
        guard let g = appGroup,
              let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: g) else { return nil }
        return dir.appendingPathComponent("widget-snapshot.json")
    }

    @discardableResult
    public static func write(_ s: WidgetSnapshot) -> Bool {
        guard let url = fileURL, let data = try? JSONEncoder().encode(s) else { return false }
        do {
            try data.write(to: url, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch { return false }
    }

    public static func read() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
