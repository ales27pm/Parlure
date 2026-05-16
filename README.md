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

## Validation
- Build CLI:
  - `cd ios && xcodebuild -project Parlure.xcodeproj -scheme Parlure -destination 'platform=iOS Simulator,name=iPhone 16' build`
- Test CLI:
  - `cd ios && xcodebuild test -project Parlure.xcodeproj -scheme Parlure -destination 'platform=iOS Simulator,name=iPhone 16'`
- Xcode:
  - Product > Test (⌘U)

ParlureTests valide notamment:
- détection/rédaction PII
- politique d’export
- décodage `qfr_import` JSONL
- échappement TSV
- fallback heuristique
- valeurs par défaut des modèles

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

## App Store AIO automation script

A high-verbosity script is included at `scripts_appstore_aio.sh` to:

- connect to your Apple Developer delivery flow using App Store Connect API credentials,
- manage signing/build defaults,
- securely store secrets in macOS Keychain,
- build IPA artifacts,
- publish to App Store Connect.

### Quick start

```bash
./scripts_appstore_aio.sh init
./scripts_appstore_aio.sh build
./scripts_appstore_aio.sh publish
# or run end-to-end:
./scripts_appstore_aio.sh all
```

Defaults are saved at `~/.config/parlure-appstore/config.env` with `600` permissions. Secret values are stored in Keychain service `parlure.appstore.aio`.


### Advanced behavior (refined)

- ASCII progress bars for each stage (init/build/publish).
- End-of-run metrics block with completed steps and elapsed seconds.
- Validation hardening:
  - strict Team ID format check (`^[A-Z0-9]{10}$`),
  - required file checks for App Store Connect key,
  - non-interactive mode for CI (`--non-interactive`) with safe defaults/fail-fast behavior.
- Error trap prints failing line and command for faster debugging.
