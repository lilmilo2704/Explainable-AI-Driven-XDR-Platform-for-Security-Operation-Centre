# Repository Instructions

## Required Read Order

Before substantial work, read:

1. `Codex.md`
2. `docs/00_PROJECT_CURRENT_STATUS.md`
3. `docs/PROJECT_STATUS_EVIDENCE.md`
4. The nearest service-level `AGENTS.md`, if one is later created.

## Source Of Truth

When sources conflict, prefer:

1. Current implementation and executable configuration.
2. Validated model metadata and dataset artifacts.
3. `docs/00_PROJECT_CURRENT_STATUS.md`.
4. Current service documentation.
5. Historical proposals and plans.

## Architecture Boundaries

- Frontend calls backend.
- Backend calls ML service.
- Frontend must not call ML service directly.
- Wazuh is the telemetry and evidence substrate.
- Backend owns orchestration, persistence, incident construction, graph assembly, and SOC report generation.

## Protected Artifacts

Do not modify without explicit permission:

- Trained teacher and surrogate models.
- Model metadata and generated explanation artifacts.
- Official dataset release ZIP.
- Official dataset exports.
- Verified evidence packages.
- Historical source/reference documents.
- Screenshots.

Protected paths include:

- `ml-service/models/teachers/**`
- `ml-service/models/surrogates/**`
- `ml-service/models/metadata/**`
- `frontend/public/model-explanations/**`
- `lab-telemetry/exports/dataset-releases/**`
- `lab-telemetry/screenshots/**`

## Current Scope Warning

- Current trained scope is binary: `Benign` versus `DoS_DDoS`.
- Current data is controlled, log-centric, and mainly application-layer service stress / single-source DoS.
- Do not claim complete, real-world, distributed, or production-grade DDoS coverage.
- The historical four-class scope is retained as project history and reference material.
- The six broader frontend incident stories are not equivalent to six trained end-to-end pipelines.

## Working Rule

Before implementing anything:

- Trace the real execution path.
- Inspect the relevant contracts.
- Compare implementation with current-status evidence.
- Do not let mock fallback hide a failed real pipeline.
