# Data governance

Parlure is designed as a local-first capture and review tool. It should be treated as a source of candidate records, not as an automatic publication or training-data approval system.

## Principles

1. Local capture first: no cloud service is added by default.
2. Review before training: records should remain `pending_review` until manually accepted.
3. Consent before training: training eligibility requires both global export approval and item-level consent.
4. PII caution: regex redaction is a safety aid, not a full anonymization guarantee.
5. Provenance preservation: exported records should retain capture type, output source, review status, consent status, and synthetic/manual flags.
6. Rejected records excluded from QFR import: raw exports may retain rejected records for audit, but training/import rows must exclude them.

## Review states

- `pending_review`: captured but not yet approved.
- `accepted`: manually approved for possible downstream use.
- `rejected`: excluded from QFR import/training paths.
- `redacted`: reviewed with sensitive content removed or reduced.

## Training eligibility

A record is training-eligible only when all of these are true:

- global export/training option is enabled;
- item-level consent is enabled;
- review status is `accepted`;
- downstream pipeline policy also accepts the source, license, PII, holdout, and provenance fields.

## PII handling

Parlure detects simple PII patterns such as emails, phone numbers, postal codes, URLs, long numbers, and selected French disclosure markers. This is not complete anonymization. Manual review remains required before public release, commercial training, or redistribution.

## Synthetic content

Assistant or heuristic outputs must be treated as synthetic components. Manual user clarifications are human-provided but still require consent, review, and PII checks.

## Downstream use

Exports should be imported into `Quec-fr-CA-llm-training-` and processed through source validation, curation, holdout filtering, permission review, and training-pack audit before any model training.