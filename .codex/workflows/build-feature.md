# Build Feature Workflow

## Purpose
Implement product features with controlled scope, contracts, tests, and documentation.

## Participating Agents
`project_orchestrator`, `repo_explorer`, relevant service specialists, `qa_reviewer`, `security_reviewer`, `docs_maintainer`

## Read First Files
`AGENTS.md`, relevant service `AGENTS.md`, `Codex.md`, `docs/00_PROJECT_CURRENT_STATUS.md`, `docs/PROJECT_STATUS_EVIDENCE.md`, and relevant patterns.

## Sequential Work
1. Create a plan under `docs/tasks/` if required by `PLANS.md`.
2. Trace the current execution path.
3. Define contract and ownership changes.
4. Implement in owned service paths only.
5. Validate tests and integration.
6. Run QA and security review.
7. Update docs.

## Parallelizable Work
Backend, frontend, ML, graph, and docs work can proceed in parallel after contracts are fixed.

## Ownership Boundaries
Backend owns orchestration/persistence, ML owns prediction/preprocessing, and frontend owns display through backend APIs only.

## Integration Gate
Real data path works or blockers are documented; mock/demo states are explicit.

## Testing Gate
Run relevant unit, contract, API, build, browser, or manual tests.

## Security Gate
Review inputs, paths, SQL, shell commands, CORS, model loading, and data exposure.

## Documentation Gate
Contracts, limitations, and status changes are documented.

## Definition Of Done
Feature works through the intended real path, validation is reported, and no protected artifacts changed.
