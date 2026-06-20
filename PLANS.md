# Planning Policy

Execution plans are required before substantial changes that affect architecture, contracts, persistence, model integration, or showcase release behavior.

Store task plans under:

```text
docs/tasks/
```

## Plan Required For

- Cross-service changes.
- API or schema changes.
- Database model, migration, or persistence changes.
- Model-contract, feature-schema, or prediction payload changes.
- Evidence import, feature validation, ML orchestration, incident, graph, or report pipeline changes.
- Showcase release work, deterministic replay, or judging runbooks.
- Any work touching protected artifacts, which also requires explicit user permission.

## Plan Contents

Each plan should include:

- Goal and non-goals.
- Read-first files.
- Ownership and participating agents.
- Current execution path and contracts.
- Proposed changes by path.
- Protected paths and how they remain untouched.
- Test, security, documentation, and integration gates.
- Rollback or failure handling.
- Definition of done.

## No Plan Needed For

- Read-only audits.
- Small documentation fixes that do not change source-of-truth status.
- Control-layer metadata updates that do not affect runtime behavior.
- Formatting-only edits in already-owned documentation.
