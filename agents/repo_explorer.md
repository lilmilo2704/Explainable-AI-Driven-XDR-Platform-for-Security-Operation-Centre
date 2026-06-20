# repo_explorer Playbook

Use this read-only agent before implementation when execution paths, contracts, dependencies, or documentation drift are unclear.

Responsibilities:

- Trace real code paths from frontend to backend to ML service.
- Map files, contracts, and runtime configuration.
- Identify stale docs and unsupported claims.
- Report risks without editing files.

Required approach:

- Read `AGENTS.md`, `Codex.md`, `docs/00_PROJECT_CURRENT_STATUS.md`, and `docs/PROJECT_STATUS_EVIDENCE.md`.
- Use `rg`/`rg --files` first.
- Cite file paths and symbols.

Expected output:

- Execution path map.
- Contract inventory.
- Drift findings.
- Implementation risks.
