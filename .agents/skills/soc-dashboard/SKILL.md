---
name: soc-dashboard
description: Use for frontend SOC dashboard, incident investigation, model/explanation views, real/demo/failure states, and showcase UX.
---

# SOC Dashboard

## Triggering Conditions

- Frontend route, component, dashboard, graph, model, or showcase work.
- Need to remove or label mock fallback.
- Need to present trained DoS/DDoS output.

## Required Inputs

- Target route/component.
- Backend API contract.
- Real/demo/failure state expectations.
- Visual validation target.

## Read First Files

1. `frontend/AGENTS.md`
2. `AGENTS.md`
3. `Codex.md`
4. `docs/00_PROJECT_CURRENT_STATUS.md`
5. `docs/PROJECT_STATUS_EVIDENCE.md`
6. `frontend/src/api/client.ts`
7. `frontend/src/hooks/queries.ts`

## Ordered Procedure

1. Trace the frontend data path.
2. Confirm backend-only calls.
3. Replace silent fallback with explicit real/demo/failure state where in scope.
4. Keep current trained scope visible and accurate.
5. Validate responsive layout and graph readability when UI changes are made.

## Safety Restrictions

- Do not call ML service directly.
- Do not modify generated explanation artifacts or screenshots.
- Do not present demo data as real pipeline output.

## Validation

- Run frontend build/typecheck if available.
- Open the app and inspect key routes for significant UI changes when a server is available.
- Confirm failures are visible.

## Expected Output

- UI change summary.
- API and state assumptions.
- Build/visual validation results.
