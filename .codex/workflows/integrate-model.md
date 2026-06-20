# Integrate Model Workflow

## Purpose
Integrate trained ML runtime behavior into backend and frontend workflows without retraining or replacing artifacts.

## Participating Agents
`project_orchestrator`, `ml_integration`, `backend_pipeline`, `frontend_showcase`, `qa_reviewer`, `security_reviewer`, `docs_maintainer`

## Read First Files
`ml-service/AGENTS.md`, `backend/AGENTS.md`, `frontend/AGENTS.md`, `Codex.md`, `docs/00_PROJECT_CURRENT_STATUS.md`, `docs/PROJECT_STATUS_EVIDENCE.md`, `ml-service/MODEL_INTEGRATION_README.md`.

## Sequential Work
1. Confirm model scope, feature schema, and endpoint contract.
2. Validate ML runtime response with representative payloads.
3. Wire backend orchestration and persistence.
4. Expose frontend display through backend APIs only.
5. Verify teacher/surrogate labels.
6. Update docs and limitations.

## Parallelizable Work
Frontend can build against an agreed backend contract with explicit demo labels while backend/ML validation proceeds.

## Ownership Boundaries
Do not retrain or replace model artifacts. Do not modify `ml-service/models/**` or `frontend/public/model-explanations/**` without explicit permission.

## Integration Gate
Backend calls ML service and persists model output with schema/version context.

## Testing Gate
Run ML endpoint checks, backend contract tests, and frontend failure-state validation.

## Security Gate
No untrusted model loading and no sensitive raw evidence exposure.

## Documentation Gate
Current trained binary scope and fallback behavior are documented.

## Definition Of Done
The trained DoS/DDoS path is integrated through backend and visible in frontend without direct frontend ML calls.
