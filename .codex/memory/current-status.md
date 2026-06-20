# Current Status Memory

- Current trained scope is binary: `Benign` versus `DoS_DDoS`.
- Official dataset batch is `training-batch-20260607T132426Z`.
- Counts: 300 planned/model-ready rows, 299 completed/exported verified runs, 798 windowed rows.
- Models: EBM, XGBoost, Random Forest, SVM, and MLP.
- EBM explains natively; non-EBM teachers use EBM surrogates.
- Current implemented service direction is `frontend -> backend -> ml-service`.
- Main gap is the unverified official-run import through trained inference, persisted incident, graph/report APIs, and real frontend view.
- Data is controlled, log-centric, Wazuh-linked, and mainly application-layer single-source DoS/service stress.
- Do not claim complete, distributed, production-grade, or real-world DDoS coverage.

## Official Run Integration Checkpoint

- Approved architecture: the first real pipeline input is raw verified logs only. Backend must reconstruct the trained model's required base features from raw verified evidence in the protected official release ZIP. The official feature CSV is only a training-serving parity oracle, not operational model input.
- Initial model: use `ebm` through the real trained run-level endpoint `POST /predict-run/ebm`, with native EBM explanations only.
- Preferred initial attack run: `attackerhostlightdos-20260607T132426Z-201`.
- Required verification before accepting that run: matching batch manifest entry exists; run is marked completed, verification passed, and exported; official feature row exists; raw-evidence folder exists in the protected ZIP; required application or nginx evidence exists; Wazuh evidence exists where expected; run is a clean supervised candidate; required files are parseable within safety limits.
- If the preferred run fails verification, select the next complete `AttackerHostLightDos` run and document the rejection reason. Plan one valid benign run later for comparison.
- Dataset access decision: use a server-side release allowlist. The API may accept only `release_id`, `run_id`, and `model_name`; it must not accept arbitrary files, directories, ZIP paths, absolute paths, or client-provided evidence roots.
- ZIP policy: read the protected ZIP directly and read-only. Do not extract over, repair, alter, or rewrite the official release. Enforce strict allowed prefixes, normalized relative paths, rejection of absolute paths/`..`/drive letters, entry size limits, total read limits, and file type allowlists.
- Database decision: use Alembic for new schema changes.
- Persistence decision: keep separate entities for `OfficialRunImport`, `EvidenceReference`, `RunPrediction`, and `IncidentRunLink`; include parity-validation state in `OfficialRunImport` or a dedicated versioned feature-extraction record.
- Idempotency rule: for the same release ID, run ID, model name, model version, raw-evidence/canonical evidence manifest hash, and reconstructed feature hash, return the existing result. Changed model version, evidence hash, or feature hash returns `409 Conflict` for this milestone.
- No-fallback rule: for the official trained pipeline, no keyword fallback, no mock fallback, no partial incident, no prediction record on ML failure; return structured `502`.
- Immediate next task: `Phase 1A - Release and Run Verification`.
- Phase 1A scope: configure allowlisted release, safely inspect ZIP, validate the selected run, build evidence inventory, and create tests for missing, incomplete, and unsafe runs.
- Phase 1A exclusions: do not parse raw evidence into canonical events beyond inventory/parseability checks, do not reconstruct model features, do not call ML, do not persist predictions/incidents, do not build graph/storyline/report APIs, do not implement frontend, do not modify model artifacts or protected dataset exports.
- Unresolved decision: endpoint protection is awaiting final approval. Recommended initial design is a demo-mode environment flag, server-side admin/demo token, and allowlisted releases only.

Sources: `Codex.md`, `.codex/memory/current-status.md`, `docs/tasks/001-official-run-model-integration.md`.
