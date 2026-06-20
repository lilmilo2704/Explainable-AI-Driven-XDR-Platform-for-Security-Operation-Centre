# ML Service Agent Instructions

## Service Responsibility

`ml-service/` is the FastAPI ML runtime. It loads trained binary `Benign` versus `DoS_DDoS` teacher models, EBM surrogate explainers, metadata, feature preprocessing, prediction endpoints, and compatibility keyword fallback behavior for demo categories.

## Files Owned

- ML runtime code and service contract documentation in `ml-service/**`
- Runtime contract docs that describe prediction payloads, preprocessing, feature schema, and teacher/surrogate behavior.

Ownership excludes protected model artifacts unless explicit permission is granted.

## Read First

1. `../AGENTS.md`
2. `../Codex.md`
3. `../docs/00_PROJECT_CURRENT_STATUS.md`
4. `../docs/PROJECT_STATUS_EVIDENCE.md`
5. `MODEL_INTEGRATION_README.md`
6. `main.py`
7. `model_runtime.py`

## Protected Files

Do not modify without explicit permission:

- `models/teachers/**`
- `models/surrogates/**`
- `models/metadata/**`
- `../frontend/public/model-explanations/**`
- `../lab-telemetry/exports/dataset-releases/**`
- `../lab-telemetry/screenshots/**`

## Required Tests

- Validate required base feature schema and engineered feature construction.
- Test `/health`, `/models`, `/predict-event`, `/analyze-window`, `/predict-run`, and model-specific run endpoints when changed.
- Confirm missing required features are rejected.
- Confirm teacher prediction and surrogate explanation fields remain distinct.
- Document if runtime dependencies prevent local execution.

## Architectural Boundaries

- ML service does not own persistence, incident construction, graph assembly, report generation, or frontend behavior.
- Backend is the caller for application workflows.
- Do not retrain, replace, or regenerate protected model, metadata, or explanation artifacts.
- Non-DDoS classes are keyword fallback/demo behavior unless new trained artifacts and contracts are explicitly approved.

## Escalation Conditions

Escalate before:

- Changing feature schema, label mapping, model versioning, or endpoint response shape.
- Loading model files from a new location.
- Touching trained artifacts or metadata.
- Claiming broader trained coverage.
- Running commands that could retrain or overwrite artifacts.
