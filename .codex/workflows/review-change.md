# Review Change Workflow

## Purpose
Review code, docs, or control-layer changes for correctness, regressions, contracts, tests, and security.

## Participating Agents
`qa_reviewer`, `security_reviewer`, `repo_explorer`, and relevant service specialists for clarification.

## Read First Files
`AGENTS.md`, `Codex.md`, `docs/00_PROJECT_CURRENT_STATUS.md`, `docs/PROJECT_STATUS_EVIDENCE.md`, relevant service `AGENTS.md`.

## Sequential Work
1. Identify changed files.
2. Review ownership and protected paths.
3. Trace behavior changes through real execution path.
4. Check tests and validation.
5. Report findings first, ordered by severity.

## Parallelizable Work
QA, security, and docs drift reviews can run independently.

## Ownership Boundaries
Review is read-only unless explicitly asked to fix.

## Integration Gate
Changed contracts remain compatible or migration is documented.

## Testing Gate
Tests are present or test gaps are explicit.

## Security Gate
Inputs, paths, commands, SQL, model loading, CORS, and data exposure reviewed.

## Documentation Gate
User-facing claims remain accurate.

## Definition Of Done
Findings, assumptions, test gaps, and residual risks are clear.
