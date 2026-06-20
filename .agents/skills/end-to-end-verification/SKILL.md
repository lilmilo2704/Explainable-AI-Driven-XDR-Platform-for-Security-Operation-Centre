---
name: end-to-end-verification
description: Use to verify the official-run-to-frontend vertical slice, service health, contract compatibility, and showcase readiness.
---

# End-to-End Verification

## Triggering Conditions

- Before declaring a feature or demo ready.
- After cross-service changes.
- When validating official clean verified replay.

## Required Inputs

- Target workflow.
- Services to run.
- Test payload or official verified replay source.
- Expected outputs.

## Read First Files

1. `AGENTS.md`
2. `Codex.md`
3. `docs/00_PROJECT_CURRENT_STATUS.md`
4. `docs/PROJECT_STATUS_EVIDENCE.md`
5. `.codex/patterns/testing.md`
6. `.codex/patterns/api-contracts.md`

## Ordered Procedure

1. Confirm no protected artifacts need modification.
2. Check service health in dependency order.
3. Validate backend -> ML contract.
4. Validate persistence and incident creation.
5. Validate graph/report APIs if in scope.
6. Validate frontend displays real output and explicit failures.
7. Record commands and results.

## Safety Restrictions

- Prefer official verified replay over live generation.
- Do not run live attack generation without explicit approval.
- Do not modify official releases, exports, verified evidence, or screenshots.

## Validation

- Health checks pass or blockers are documented.
- Contract checks pass.
- UI/API failure states are explicit.
- `git diff --check` passes for code/doc changes.

## Expected Output

- Verification report.
- Commands and results.
- Blockers and residual risks.
