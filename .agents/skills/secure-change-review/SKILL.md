---
name: secure-change-review
description: Use for security review of evidence parsing, backend APIs, frontend exposure, ML loading, lab scripts, and destructive command risk.
---

# Secure Change Review

## Triggering Conditions

- Changes parse evidence, accept paths, call shell commands, load models, alter CORS, expose raw data, or run lab scripts.
- User requests a security review.

## Required Inputs

- Diff or target files.
- Threat model or affected workflow.
- Commands run, if any.

## Read First Files

1. `AGENTS.md`
2. `docs/00_PROJECT_CURRENT_STATUS.md`
3. `docs/PROJECT_STATUS_EVIDENCE.md`
4. `.codex/patterns/security.md`
5. Relevant service `AGENTS.md`

## Ordered Procedure

1. Identify trust boundaries and untrusted inputs.
2. Check path traversal, command injection, SQL injection, unsafe deserialization/model loading, CORS, and sensitive data exposure.
3. Check destructive lab command risk and protected path writes.
4. Verify failures are visible and not hidden by fallback.
5. Rank findings by severity with file references.

## Safety Restrictions

- Read-only unless separately assigned to fix.
- Do not print secrets or sensitive raw evidence.
- Do not execute destructive commands.

## Validation

- Findings cite files and behaviors.
- False positives are marked as assumptions.
- Residual risk is explicit.

## Expected Output

- Security findings first.
- Required mitigations.
- Residual risk and test gaps.
