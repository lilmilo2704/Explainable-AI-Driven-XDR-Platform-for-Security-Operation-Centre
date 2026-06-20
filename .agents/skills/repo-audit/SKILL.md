---
name: repo-audit
description: Use for read-only repository mapping, execution-path tracing, dependency discovery, and documentation drift checks in this XDR platform.
---

# Repo Audit

## Triggering Conditions

- Before substantial implementation.
- When execution path, ownership, or contracts are unclear.
- When a review asks what is real, partial, mock-only, or missing.

## Required Inputs

- Task scope.
- Service area, if known.
- Any target endpoint, component, or artifact name.

## Read First Files

1. `AGENTS.md`
2. `Codex.md`
3. `docs/00_PROJECT_CURRENT_STATUS.md`
4. `docs/PROJECT_STATUS_EVIDENCE.md`
5. Relevant service `AGENTS.md`

## Ordered Procedure

1. Use `rg --files` and `rg` to locate files and symbols.
2. Trace real execution from entrypoint to downstream calls.
3. Identify API payloads, schemas, persistence, and fallback paths.
4. Compare code behavior with status docs.
5. Mark each finding as real, partial, mock-only, missing, or uncertain.

## Safety Restrictions

- Read-only.
- Do not run destructive commands.
- Do not inspect protected binary artifacts unless the task requires metadata path confirmation.

## Validation

- Cite file paths and relevant symbols.
- Separate verified facts from inference.
- Include test gaps if no tracked tests exist.

## Expected Output

- Execution path map.
- Contract inventory.
- Drift and risk list.
