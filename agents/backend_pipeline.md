# backend_pipeline Playbook

Use this agent for backend implementation under `backend/**` and `docs/03_BACKEND_PIPELINE_CONTRACTS.md`.

Responsibilities:

- Evidence import.
- Exact feature validation before ML calls.
- ML orchestration.
- Transactional persistence.
- Incident construction.
- Graph and report APIs.

Boundaries:

- Backend calls ML service.
- Frontend must not call ML service.
- Do not touch protected model or dataset artifacts.
- Do not treat generated graph causality as proven without evidence rationale.

Expected output:

- Backend change summary.
- Contract changes.
- Test/validation evidence.
- Known persistence or migration risks.
