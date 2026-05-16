# Parlure iOS

Parlure est une application iOS locale pour capter la parole en français québécois (fr-CA), conserver dialogues + clarifications, puis exporter des données vers `Quec-fr-CA-llm-training`.

## Confidentialité et révision
- 100% local (aucun service cloud ajouté).
- Statuts de révision: `pending_review`, `accepted`, `rejected`, `redacted`.
- Règle de consentement entraînement:
  - `consent_for_training = true` **seulement si** export global autorisé + consentement item activé + statut `accepted`.
- Politique d’export:
  - Raw exports incluent **tous** les enregistrements (incluant rejetés).
  - QFR import JSONL exclut les enregistrements `rejected`.
  - Les champs PII et `redacted_text` sont produits localement.

## Build/Test
- Build:
  - `cd ios && xcodebuild -project Parlure.xcodeproj -scheme Parlure -destination 'platform=iOS Simulator,name=iPhone 16' build`
- Tests:
  - `cd ios && xcodebuild test -project Parlure.xcodeproj -scheme Parlure -destination 'platform=iOS Simulator,name=iPhone 16'`

## Exports produits
- `parlure_<timestamp>_dialogues.raw.jsonl`
- `parlure_<timestamp>_glossary.raw.jsonl`
- `parlure_<timestamp>_qfr_import.jsonl`
- `parlure_<timestamp>_parallel.tsv`
- `parlure_<timestamp>_meta.json`

## Limites connues
- La disponibilité Speech dépend de l’appareil/locale.
- FoundationModels est optionnel et seulement sur plateformes supportées.
- Réviser/rédiger les données avant usage d’entraînement production/commercial.
- Les réponses assistant sont synthétiques, pas un corpus humain pur.

## Migration smoke test (manuel)
1. Installer/exécuter la version main et créer 1 dialogue + 1 entrée glossaire.
2. Fermer l’app.
3. Installer cette branche PR sur le même simulateur/appareil.
4. Relancer et vérifier que l’Archive s’ouvre et que les anciennes données sont migrées, ou qu’une erreur claire/récupérable est affichée.
