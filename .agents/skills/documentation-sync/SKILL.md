---
name: documentation-sync
description: Use to align README, service docs, AGENTS files, memory, workflows, and status documents with verified repository state.
---

# Documentation Sync

## Triggering Conditions

- Docs disagree with verified project status.
- New contracts, workflows, or limitations need documentation.
- Stale mock-only or six-scenario claims need correction.

## Required Inputs

- Files to update.
- Verified source of truth.
- Change scope.

## Read First Files

1. `AGENTS.md`
2. `Codex.md`
3. `docs/00_PROJECT_CURRENT_STATUS.md`
4. `docs/PROJECT_STATUS_EVIDENCE.md`
5. `.codex/patterns/documentation.md`

## Ordered Procedure

1. Identify stale or unsupported claims.
2. Trace each replacement claim to evidence.
3. Update only documentation files in scope.
4. Preserve historical documents unless explicitly asked to edit them.
5. Keep limitations and current trained scope visible.

## Safety Restrictions

- Do not change runtime code.
- Do not modify protected artifacts.
- Do not fabricate metrics, implementation status, or model coverage.

## Validation

- Run markdown sanity checks when available.
- Run `git diff --check`.
- Confirm changed docs cite or align with status evidence.

## Expected Output

- Documentation changes.
- Source mapping.
- Remaining drift.
