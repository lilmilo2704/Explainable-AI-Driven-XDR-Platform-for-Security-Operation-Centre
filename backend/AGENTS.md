# Backend Agent Instructions

## Service Responsibility

`backend/` is the FastAPI orchestration layer. It owns alert ingestion, evidence import plans, normalization, ML-service orchestration, PostgreSQL persistence, incident construction, graph assembly, asset/case derivation, and future SOC report APIs.

## Files Owned

- `backend/**`
- `docs/03_BACKEND_PIPELINE_CONTRACTS.md`
- Backend-facing contract sections in `docs/tasks/**`

## Read First

1. `../AGENTS.md`
2. `../Codex.md`
3. `../docs/00_PROJECT_CURRENT_STATUS.md`
4. `../docs/PROJECT_STATUS_EVIDENCE.md`
5. `../README.md`
6. Relevant backend execution path files under `backend/app/**`

## Protected Files

Do not modify protected artifacts through backend work:

- `../ml-service/models/teachers/**`
- `../ml-service/models/surrogates/**`
- `../ml-service/models/metadata/**`
- `../frontend/public/model-explanations/**`
- `../lab-telemetry/exports/dataset-releases/**`
- `../lab-telemetry/screenshots/**`
- Historical source/reference documents unless explicitly requested.

## Required Tests

- For API changes: backend route/schema tests or explicit manual request validation.
- For persistence changes: transaction/rollback checks and database schema verification.
- For ML orchestration changes: contract test against ML-service payload shape.
- For incident/graph/report changes: serialization tests with evidence provenance.
- If tests are absent, document the gap and run the narrowest available validation.

## Architectural Boundaries

- Backend calls ML service.
- Frontend calls backend only.
- Backend must not let mock/demo seed behavior hide failed real pipeline execution.
- Wazuh and official evidence remain provenance inputs, not ground-truth labels by themselves.
- Persist model/schema versions and evidence links where pipeline output is durable.

## Escalation Conditions

Escalate before:

- Changing database schema, persistence semantics, or migration strategy.
- Adding an official dataset/evidence importer.
- Introducing report-generation output contracts.
- Running lab commands that modify evidence or services.
- Touching protected artifacts or Docker service behavior.
