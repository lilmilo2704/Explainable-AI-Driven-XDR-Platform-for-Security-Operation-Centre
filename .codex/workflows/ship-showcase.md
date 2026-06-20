# Ship Showcase Workflow

## Purpose
Prepare a deterministic judging/demo showcase based on verified evidence and honest limitations.

## Participating Agents
`project_orchestrator`, `demo_engineer`, `backend_pipeline`, `ml_integration`, `frontend_showcase`, `evidence_graph`, `qa_reviewer`, `security_reviewer`, `docs_maintainer`

## Read First Files
`AGENTS.md`, `Codex.md`, `docs/00_PROJECT_CURRENT_STATUS.md`, `docs/PROJECT_STATUS_EVIDENCE.md`, `.codex/memory/current-status.md`, `.codex/memory/known-issues.md`.

## Sequential Work
1. Choose official verified replay over live attack generation.
2. Verify service health and reset/replay steps.
3. Validate backend -> ML inference and persistence.
4. Validate incident, graph, explanation, response guidance, and report readiness.
5. Validate frontend display and failure states.
6. Document demo runbook and limitations.

## Parallelizable Work
Service health checks, frontend visual checks, contract validation, and runbook review.

## Ownership Boundaries
Do not modify official releases, exports, verified evidence, screenshots, model artifacts, or Docker service behavior. Live telemetry generation requires explicit approval.

## Integration Gate
End-to-end path is replayable or blockers are documented.

## Testing Gate
Health, API, ML, persistence, frontend build, and browser checks as applicable.

## Security Gate
No destructive lab operations; no sensitive raw evidence or secrets exposed.

## Documentation Gate
Demo runbook states binary trained scope, dataset facts, and limitations.

## Definition Of Done
Showcase can be replayed deterministically and its claims match verified evidence.
