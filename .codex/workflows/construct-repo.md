# Construct Repo Workflow

## Purpose
Create or adjust repository control structure, plans, docs, and non-runtime scaffolding safely.

## Participating Agents
`project_orchestrator`, `system_architect`, `repo_explorer`, `docs_maintainer`, `qa_reviewer`

## Read First Files
`AGENTS.md`, `Codex.md`, `docs/00_PROJECT_CURRENT_STATUS.md`, `docs/PROJECT_STATUS_EVIDENCE.md`, `PLANS.md`.

## Sequential Work
1. `repo_explorer` confirms existing structure and conflicts.
2. `system_architect` validates boundaries and naming.
3. `docs_maintainer` creates or updates control docs.
4. `qa_reviewer` checks no runtime/protected files changed.

## Parallelizable Work
Agent config drafting, workflow drafting, pattern drafting, and memory drafting.

## Ownership Boundaries
Do not move `backend/`, `frontend/`, `ml-service/`, or `lab-telemetry/`. Do not create a root `src/`. Do not change Docker service behavior.

## Integration Gate
New files are discoverable and consistent with service boundaries.

## Testing Gate
Validate JSON, TOML, YAML/front matter, Python hook compilation, and `git diff --check`.

## Security Gate
Hooks must only inspect, warn, or block. They must not modify source, commit, push, retrain, recurse agents, or bypass approvals.

## Documentation Gate
Control docs cite current status and protected paths.

## Definition Of Done
Control layer exists, validates cleanly, and only expected non-runtime files changed.
