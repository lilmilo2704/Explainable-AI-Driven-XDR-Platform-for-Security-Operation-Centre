---
name: ml-contract-validation
description: Use to validate ML runtime endpoints, feature schema, model metadata, teacher/surrogate distinction, and backend integration contracts.
---

# ML Contract Validation

## Triggering Conditions

- ML endpoint or payload changes.
- Backend integration with `/predict-event`, `/analyze-window`, or `/predict-run*`.
- Model metadata or UI model display changes.

## Required Inputs

- Endpoint under test.
- Example payload or run row.
- Expected feature schema.
- Expected teacher/surrogate behavior.

## Read First Files

1. `ml-service/AGENTS.md`
2. `Codex.md`
3. `docs/00_PROJECT_CURRENT_STATUS.md`
4. `docs/PROJECT_STATUS_EVIDENCE.md`
5. `ml-service/main.py`
6. `ml-service/model_runtime.py`
7. `ml-service/MODEL_INTEGRATION_README.md`

## Ordered Procedure

1. Confirm current trained scope is `Benign` versus `DoS_DDoS`.
2. Confirm required base features and engineered features.
3. Validate endpoint request and response shape.
4. Confirm teacher prediction fields are separate from surrogate explanation fields.
5. Confirm missing features fail clearly.
6. Confirm broader non-DDoS behavior is labelled fallback/demo.

## Safety Restrictions

- Do not retrain models.
- Do not modify teacher, surrogate, metadata, or explanation artifacts.
- Do not load models from untrusted paths.

## Validation

- Run endpoint checks when the service is available.
- Run unit/contract tests if present.
- Document dependency or runtime blockers.

## Expected Output

- Contract validation result.
- Feature schema result.
- Teacher/surrogate distinction notes.
- Any integration blockers.
