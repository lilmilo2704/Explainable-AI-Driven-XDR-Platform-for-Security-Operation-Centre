# Update Current Status Workflow

## Purpose
Keep project status, memory, and documentation aligned with verified implementation evidence.

## Participating Agents
`project_orchestrator`, `repo_explorer`, `docs_maintainer`, `qa_reviewer`

## Read First Files
`AGENTS.md`, `Codex.md`, `docs/00_PROJECT_CURRENT_STATUS.md`, `docs/PROJECT_STATUS_EVIDENCE.md`, relevant service README or `AGENTS.md`.

## Sequential Work
1. `repo_explorer` maps current implementation evidence.
2. `docs_maintainer` compares claims with approved status evidence.
3. `project_orchestrator` resolves conflicts by source-of-truth order.
4. `qa_reviewer` checks unsupported claims and test gaps.

## Parallelizable Work
Service evidence checks, README drift checks, and memory review.

## Ownership Boundaries
Documentation only unless the user explicitly asks for code changes. Do not edit protected historical/reference documents unless requested.

## Integration Gate
Every material claim maps to implementation, validated metadata/artifacts, or approved status docs.

## Testing Gate
Run `git diff --check` and relevant markdown/front-matter checks.

## Security Gate
Do not add secrets, sensitive raw evidence, or unnecessary absolute local paths.

## Documentation Gate
Docs must state current binary trained scope and limitations.

## Definition Of Done
Status claims are sourced, concise, and do not overstate DDoS or multi-class coverage.
