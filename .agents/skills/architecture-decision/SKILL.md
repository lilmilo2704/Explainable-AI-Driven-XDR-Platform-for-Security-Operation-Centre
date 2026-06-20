---
name: architecture-decision
description: Use when proposing ADRs, schemas, service boundaries, migrations, or cross-service design for the XDR platform.
---

# Architecture Decision

## Triggering Conditions

- Cross-service change.
- API/schema/database/model-contract change.
- New graph, report, evidence import, or dashboard architecture.

## Required Inputs

- Problem statement.
- Current execution path.
- Affected services and contracts.
- Constraints and protected paths.

## Read First Files

1. `AGENTS.md`
2. `Codex.md`
3. `docs/00_PROJECT_CURRENT_STATUS.md`
4. `docs/PROJECT_STATUS_EVIDENCE.md`
5. `PLANS.md`
6. `.codex/patterns/api-contracts.md`
7. `.codex/patterns/evidence-provenance.md`

## Ordered Procedure

1. Define the decision and non-goals.
2. Preserve `frontend -> backend -> ml-service`.
3. Document current behavior and gap.
4. Propose contract/schema changes with versioning.
5. Define migration, testing, security, and documentation gates.
6. Record tradeoffs and rejected options.

## Safety Restrictions

- Do not move services into a root `src/` directory.
- Do not alter runtime code while only drafting a decision.
- Do not broaden trained model claims.

## Validation

- Confirm service boundary preservation.
- Confirm protected paths remain untouched.
- Confirm plan exists under `docs/tasks/` when required.

## Expected Output

- ADR or task plan.
- Contract and schema implications.
- Gate checklist.
