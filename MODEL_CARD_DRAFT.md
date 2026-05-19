# Model Card Draft — Parlure local decision layer

Parlure is not a released foundation model. This file documents the local decision layer used by the app.

## System description

Parlure combines deterministic Québec French heuristics, local glossary retrieval, and optional Apple FoundationModels support when available on the user's device.

## Intended use

- Assist local capture of Québec French speech and expressions.
- Ask for clarification when a term or phrase is unclear.
- Use local glossary context to avoid repeating the same clarification.
- Generate short assistant responses that help structure candidate training records.

## Not intended for

- Legal, medical, financial, or safety-critical advice.
- Autonomous public dataset publication.
- Automatic model training without review.
- Complete anonymization or consent management by itself.

## Synthetic-output warning

Assistant, heuristic, glossary-assisted, or FoundationModels outputs must be marked as synthetic or assistant-generated unless manually authored by a user. Downstream training pipelines should preserve this distinction.

## Known limitations

- Heuristics cover only selected Québec French expressions.
- Optional FoundationModels output availability depends on Apple platform support.
- Speech recognition can mis-transcribe dialectal or noisy audio.
- PII redaction is incomplete and must be followed by manual review.

## Evaluation status

The project includes regression tests for grounding, clarification behaviour, export eligibility, PII handling, glossary matching, and synthetic/manual flags. This is not a full linguistic benchmark.