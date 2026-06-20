# Fix Bug Workflow

## Purpose
Fix a defect with minimal blast radius and clear regression validation.

## Participating Agents
`repo_explorer`, relevant service specialist, `qa_reviewer`, `security_reviewer` when security-sensitive, `docs_maintainer` if behavior/docs change.

## Read First Files
`AGENTS.md`, relevant service `AGENTS.md`, `docs/00_PROJECT_CURRENT_STATUS.md`, `docs/PROJECT_STATUS_EVIDENCE.md`.

## Sequential Work
1. Reproduce or trace the bug.
2. Identify root cause and affected contract.
3. Patch the narrowest owned files.
4. Add or run focused regression checks.
5. Document remaining risk.

## Parallelizable Work
QA can inspect regression area while implementation proceeds; security review can run in parallel for parsing, path, command, SQL, or exposure bugs.

## Ownership Boundaries
Do not refactor unrelated areas, change protected artifacts, or mask failures with fallback.

## Integration Gate
Bug is fixed on the real execution path.

## Testing Gate
Regression command or manual check demonstrates the fix.

## Security Gate
Fix does not introduce unsafe parsing, commands, SQL, CORS, or data exposure.

## Documentation Gate
Update docs only if user-facing behavior or known limitations changed.

## Definition Of Done
Root cause and validation are reported, with protected paths unchanged.
