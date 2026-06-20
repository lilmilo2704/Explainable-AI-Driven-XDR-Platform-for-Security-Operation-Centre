---
name: project-status-sync
description: Use when Codex must reconcile repository claims with the approved XDR project status files or update status memory without changing runtime code.
---

# Project Status Sync

## Triggering Conditions

- A task asks for current scope, dataset, model, implementation status, or limitations.
- Documentation or memory may be stale.
- A change could affect claims about trained coverage, dataset counts, or demo readiness.

## Required Inputs

- Task request.
- Relevant changed files, if any.
- Current git status.

## Read First Files

1. `AGENTS.md`
2. `Codex.md`
3. `docs/00_PROJECT_CURRENT_STATUS.md`
4. `docs/PROJECT_STATUS_EVIDENCE.md`
5. `.codex/memory/current-status.md`

## Ordered Procedure

1. Load the read-first files.
2. Identify the claim being checked or updated.
3. Compare the claim against implementation evidence and status evidence.
4. Prefer current implementation, validated metadata/artifacts, then status docs.
5. Update only approved status/memory/docs files when explicitly requested.
6. Keep historical four-class scope separate from current trained binary scope.

## Safety Restrictions

- Do not modify runtime code.
- Do not modify protected model, dataset, evidence, screenshot, or historical reference artifacts.
- Do not fabricate metrics or coverage.

## Validation

- Confirm citations point to repository files.
- Run markdown/front-matter checks if skills or memory files changed.
- Run `git diff --check`.

## Expected Output

- Concise status summary or documentation update.
- Source file citations.
- Remaining uncertainties.
