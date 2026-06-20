---
name: backend-model-pipeline
description: Use for backend work that imports evidence, validates exact features, calls ML service, persists predictions/incidents, or exposes graph/report APIs.
---

# Backend Model Pipeline

## Triggering Conditions

- Backend evidence import or feature validation work.
- Backend -> ML service orchestration.
- Prediction, incident, graph, or report API changes.

## Required Inputs

- Target endpoint or workflow.
- Current backend schemas and services.
- ML contract details.
- Evidence source assumptions.

## Read First Files

1. `backend/AGENTS.md`
2. `AGENTS.md`
3. `Codex.md`
4. `docs/00_PROJECT_CURRENT_STATUS.md`
5. `docs/PROJECT_STATUS_EVIDENCE.md`
6. `backend/app/main.py`
7. `backend/app/services/ml_client.py`
8. `backend/app/services/ingestion_service.py`
9. `backend/app/services/serialization.py`

## Ordered Procedure

1. Trace the current backend execution path.
2. Identify input schema and evidence provenance fields.
3. Validate exact ML base features before inference.
4. Call ML service through backend client only.
5. Persist predictions, explanations, evidence links, incidents, and graph/report data transactionally.
6. Expose explicit real/demo/failure states.

## Safety Restrictions

- Do not modify ML artifacts or official dataset releases.
- Do not let mock seed/fallback hide real pipeline failure.
- Do not infer causal proof from temporal order alone.

## Validation

- Run available backend tests or targeted API checks.
- Validate database changes and rollback behavior.
- Confirm ML payload matches contract.

## Expected Output

- Backend implementation summary.
- Contract and persistence notes.
- Test evidence and remaining gaps.
