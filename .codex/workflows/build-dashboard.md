# Build Dashboard Workflow

## Purpose
Build or improve SOC analyst dashboard and incident investigation UI using real backend output as the primary source.

## Participating Agents
`project_orchestrator`, `frontend_showcase`, `backend_pipeline`, `evidence_graph`, `qa_reviewer`, `docs_maintainer`

## Read First Files
`frontend/AGENTS.md`, `backend/AGENTS.md`, `Codex.md`, `docs/00_PROJECT_CURRENT_STATUS.md`, `docs/PROJECT_STATUS_EVIDENCE.md`, `.codex/patterns/frontend.md`.

## Sequential Work
1. Trace the frontend data path.
2. Confirm backend APIs and missing fields.
3. Define UI states for real, demo, loading, empty, and failure.
4. Implement frontend changes.
5. Validate graph, evidence, and model labels.
6. Run build and visual checks when possible.

## Parallelizable Work
Backend can expose missing read-only fields while frontend builds against an agreed contract; graph semantics can be reviewed in parallel.

## Ownership Boundaries
Frontend calls backend only. Demo/mock content must be labelled. Do not modify screenshots or generated explanation artifacts.

## Integration Gate
UI uses backend APIs for real pipeline data.

## Testing Gate
Run frontend build/typecheck and browser/manual route validation for significant UI changes.

## Security Gate
No sensitive raw evidence leaks to UI; API failures are visible.

## Documentation Gate
Dashboard design docs are updated if behavior or claims change.

## Definition Of Done
Dashboard supports analyst workflow with honest real/demo/failure states.
