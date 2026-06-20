# Frontend Agent Instructions

## Service Responsibility

`frontend/` is the React/Vite SOC analyst UI. It presents dashboard, alerts, incidents, incident detail, assets, cases, coverage, models, graphs, model explanations, evidence provenance, and future report-ready views.

## Files Owned

- `frontend/**`
- `docs/05_FRONTEND_DASHBOARD_DESIGN.md`
- Frontend-facing contract sections in `docs/tasks/**`

## Read First

1. `../AGENTS.md`
2. `../Codex.md`
3. `../docs/00_PROJECT_CURRENT_STATUS.md`
4. `../docs/PROJECT_STATUS_EVIDENCE.md`
5. `README.md`
6. `src/api/client.ts`
7. `src/hooks/queries.ts`
8. Relevant route/page/component files for the requested change.

## Protected Files

Do not modify without explicit permission:

- `public/model-explanations/**`
- `../ml-service/models/**`
- `../lab-telemetry/exports/dataset-releases/**`
- `../lab-telemetry/screenshots/**`
- Historical source/reference documents.

## Required Tests

- For UI behavior: build or typecheck when available.
- For API integration: verify backend endpoints and failure states.
- For graph work: inspect rendered graph data and provenance labels.
- For showcase work: verify real, demo, and failure states are visible and not silently conflated.

## Architectural Boundaries

- Frontend must call backend only.
- Do not call ML-service endpoints directly from frontend code.
- Real backend pipeline output is the primary data source.
- Demo/mock data must be explicit and must not hide API failures.
- Current trained scope is `Benign` versus `DoS_DDoS`; broader stories are demo/keyword fallback unless proven otherwise.

## Escalation Conditions

Escalate before:

- Changing API contracts consumed by backend.
- Adding or changing mock fallback behavior.
- Reframing model coverage, metrics, or dataset claims.
- Touching generated explanation artifacts or screenshots.
- Changing Docker service behavior or frontend deployment assumptions.
