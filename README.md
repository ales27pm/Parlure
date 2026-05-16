# Parlure iOS

Parlure est une app iOS locale pour capter la parole en français québécois (fr-CA), conserver les dialogues/glossaire, puis exporter des jeux de données pour `Quec-fr-CA-llm-training`.

## Confidentialité
- 100% local: pas de cloud.
- Export marqué sensible par défaut.
- Révision recommandée avant tout usage entraînement.
- Réponses assistant = composante synthétique.

## Exigences
- Xcode récent (target iOS 18+).
- Speech + microphone permissions.
- FoundationModels est optionnel et strictement gardé par disponibilité.

## Build
1. Ouvrir `ios/Parlure.xcodeproj`.
2. Choisir un simulateur/appareil iOS.
3. Build & Run.

## Formats d’export
- `parlure_<ts>_dialogues.raw.jsonl`
- `parlure_<ts>_glossary.raw.jsonl`
- `parlure_<ts>_qfr_import.jsonl`
- `parlure_<ts>_parallel.tsv`
- `parlure_<ts>_meta.json`

## Import vers Quec-fr-CA-llm-training
Utiliser `*_qfr_import.jsonl` (champs `text` et `content` inclus), puis filtrer selon `review_status`, `consent_for_training`, et flags PII.

## Limites connues
- Disponibilité Speech varie selon appareil/locale.
- FoundationModels n’est pas universel.
- Les exports demandent révision/redaction avant entraînement.
- Sorties synthétiques ne doivent pas être traitées comme corpus humain pur.
