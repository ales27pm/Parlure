# Dataset Card Draft — Parlure exports

Parlure exports are candidate local records for Québec French data governance workflows. They are not automatically public datasets.

## Dataset sources

- User speech transcripts captured locally through iOS speech recognition.
- User-provided clarifications of Québec French expressions.
- Assistant or heuristic responses generated inside the app.
- Optional redacted text produced by local PII detection/redaction helpers.

## Languages

- Primary language: `fr-CA`
- Dialect focus: Québec French

## Record classes

- `dialogue_pair`
- `idiom_clarification`

## Consent and review

Records must be filtered by:

- `review_status`
- `consent_for_training`
- `contains_personal_data`
- `detected_pii`
- `requires_review`
- `synthetic_component` / `synthetic_output`
- downstream source and license policy

## Recommended downstream policy

- Use raw exports for audit only.
- Use `*_qfr_import.jsonl` for downstream QFR ingestion.
- Exclude rejected records.
- Treat pending records as review-required.
- Treat assistant-generated outputs as synthetic.
- Never publish or train commercially without explicit consent and manual review.

## Known limitations

- Speech transcription errors may occur.
- PII redaction is incomplete.
- Assistant outputs are synthetic and may contain errors.
- User consent must be interpreted conservatively.
