# Cockpit — pilotage financier pour freelance (macOS)

App native macOS (SwiftUI, macOS 15+) avec widget WidgetKit. Locale, privée, sans compte ni cloud.

## Lancer

```bash
xcodegen generate            # régénère Cockpit.xcodeproj depuis project.yml
open Cockpit.xcodeproj       # puis ⌘R sur le schéma « Cockpit »
```

En ligne de commande :

```bash
xcodebuild -project Cockpit.xcodeproj -scheme Cockpit -derivedDataPath build/DD build
open build/DD/Build/Products/Debug/Cockpit.app
```

Données d'exemple (dossier séparé, tes vraies données ne sont pas touchées) : `scripts/demo.sh` (`--reset` pour repartir de zéro).

Tests du moteur (45 tests) : `cd CockpitCore && swift test`.

## Architecture

| Couche | Emplacement |
|---|---|
| Montants exacts (centimes `Int64`, arrondi explicite) | `CockpitCore/Sources/CockpitCore/Money.swift` |
| Modèle de données | `Models.swift`, `Ledger.swift` (opérations métier : émission, paiements, avoirs, devis) |
| Règles fiscales sourcées et datées | `TaxRules.swift` (catalogue), `TaxEngine.swift` (obligations, échéances, réserves) |
| Tableau de bord, trésorerie, rentabilité | `FinanceEngine.swift` |
| Prévisions 30/60/90 j, 3 scénarios | `Forecast.swift` |
| Recommandations chiffrées | `Insights.swift` |
| Import CSV, relances, instantané widget | `Services.swift`, `SharedSnapshot.swift` |
| Persistance JSON atomique, migrations, sauvegardes | `Persistence.swift` |
| Interface SwiftUI | `App/` (tokens et composants dans `Design.swift`, PDF dans `DocumentPDF.swift`) |
| Widget | `Widget/` (timeline) + `Shared/WidgetViews.swift` (vues partagées avec l'aperçu de l'app) |

Le moteur ne dépend pas de SwiftUI : tous les calculs sont testés unitairement.

## Données et confidentialité

- Stockage : `~/Library/Containers/fr.cockpit.app/Data/Library/Application Support/Cockpit/` (`ledger.json`, `Backups/`, `Justificatifs/`), fichiers en 0600.
- App sandboxée **sans droit réseau** : elle ne peut rien envoyer. Pas de télémétrie, pas d'IA externe, pas de connexion bancaire.
- Sauvegarde automatique quotidienne (30 conservées) + avant chaque migration ou restauration. Export / restauration depuis Réglages › Données.

## Widget : activer le partage de données (phase 2)

Sans compte Apple Developer, l'App Group n'existe pas : le widget se compile et s'installe, mais il affiche « Ouvre Cockpit ». L'aperçu fidèle est visible dans Réglages › Données. Avec ton équipe :

1. Ouvre `Config/Signing.xcconfig` et renseigne :
   ```
   DEVELOPMENT_TEAM = ABCDE12345
   COCKPIT_APP_GROUP = ABCDE12345.fr.cockpit.shared
   COCKPIT_ENTITLEMENTS_VARIANT = AppGroup
   ```
2. Dans `project.yml`, retire `CODE_SIGN_IDENTITY: "-"`, puis lance `xcodegen generate` et compile.

Le widget est rechargé par l'app à chaque modification. À défaut, il se rafraîchit au plus toutes les heures, dans la limite du budget accordé par macOS, et affiche toujours l'heure de calcul.

## Règles fiscales (vérifiées le 21/10/2026)

Régime micro-entrepreneur, sources : entreprendre.service-public.gouv.fr.

| Règle | Valeur 2026 | Source |
|---|---|---|
| Cotisations vente / BIC services / BNC SSI / BNC Cipav | 12,3 % / 21,2 % / 25,6 % / 23,2 % du CA encaissé | F36232 |
| Versement libératoire vente / BIC / BNC | 1 % / 1,7 % / 2,2 % | F23267 |
| Abattements micro-fiscaux | 71 % / 50 % / 34 % (min. 305 €) | F23267 |
| Plafonds micro | 203 100 € / 83 600 € | F23267 |
| Franchise TVA (base / majoré) | vente 85 000 / 93 500 € ; services 37 500 / 41 250 € | F21746 |
| CFP | 0,1 % commerce, 0,3 % artisan, 0,2 % libéral — **à vérifier** (calendrier) | F23459 |
| Échéances URSSAF | mensuel : fin du mois suivant ; trimestriel : 30/4, 31/7, 31/10, 31/1 ; report au jour ouvré | F23257 |

Toutes ces valeurs sont modifiables (Réglages › Règles fiscales, avec confirmation et versionnage par date d'effet).

## Limites connues

- **Années antérieures à 2026** : aucun taux vérifié. Les périodes avec du chiffre d'affaires sont marquées « à vérifier », sans estimation inventée.
- **CFP** : service-public décrit un versement annuel en novembre, alors que le portail autoentrepreneur l'intègre aux déclarations. L'app l'estime par période et l'affiche « à vérifier ».
- **ACRE** : la réduction n'est pas calculée automatiquement. Saisis le taux réellement appliqué (Réglages › Profil › taux exact URSSAF).
- **Impôt sur le revenu** (hors versement libératoire) : estimation indicative à partir de ton taux de prélèvement à la source. Il n'y a pas de calcul du foyer fiscal.
- **TVA** (si redevable) : collectée sur les encaissements, déductible sur les dépenses payées. La date de dépôt exacte dépend de ton SIE et reste « à vérifier ».
- **Formes juridiques autres que la micro-entreprise** : pas de calcul automatique, il faut l'avis d'un expert-comptable.
- **Remboursement après un avoir** : il n'est pas modélisé. Les paiements reçus restent comptés comme encaissés.
- **Jours fériés** : seuls les jours fériés nationaux de métropole sont gérés pour les reports d'échéance.
