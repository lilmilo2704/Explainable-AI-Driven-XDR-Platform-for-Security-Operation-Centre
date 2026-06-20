# Decision Log

- Preserve the existing top-level service layout: `backend/`, `frontend/`, `ml-service/`, and `lab-telemetry/`.
- Do not create a generic root `src/` directory.
- Treat Wazuh as the telemetry and evidence substrate.
- Backend owns orchestration, persistence, incident construction, graph assembly, and SOC report generation.
- Frontend calls backend only.
- ML service owns runtime model loading, preprocessing parity, prediction contracts, and teacher/surrogate distinction.
- Keep historical four-class scope as reference only until broader trained pipelines exist.
- Prefer official verified replay over live attack generation for judging and demos.

Sources: `AGENTS.md`, `Codex.md`, `docs/00_PROJECT_CURRENT_STATUS.md`.
