# Codex Project Memory

## Project Purpose

This repository is intended to become an incident-centric SOC/XDR prototype. The product goal is to help analysts move from raw telemetry and alert fragments to evidence-backed incidents, model explanations, causal graphs, response guidance, and eventually deterministic SOC reports.

The analyst value is not just classification. The system should preserve evidence provenance, explain why a model or rule believed an incident occurred, show how evidence supports the incident story, and let analysts investigate without confusing mock/demo data for validated runtime output.

Material claims in this file are traceable in `docs/PROJECT_STATUS_EVIDENCE.md`.

## Current Repository Structure

- `backend/`: FastAPI orchestration prototype. It implements alert ingestion, normalization, ML-service calls, PostgreSQL persistence, incident creation, timeline/graph serialization, dashboard summary, asset/case derivation, mock seed, and reset endpoints.
- `frontend/`: React/Vite analyst UI. It implements routes for dashboard, alerts, incidents, incident detail, assets, cases, coverage, and models. It uses React Query and React Flow, but relies heavily on mock fallback.
- `ml-service/`: FastAPI ML runtime. It loads trained binary `Benign` vs `DoS_DDoS` models and EBM explanation/surrogate artifacts. It also keeps a keyword fallback classifier for broader demo incident categories.
- `lab-telemetry/`: Local lab telemetry toolkit, historical/current documentation, automation scripts, screenshots, and the protected official dataset release ZIP. The extracted clean release folder is partial; the ZIP is the complete protected package.
- PostgreSQL: provided by `docker-compose.yml` as `db`, used by the backend through `DATABASE_URL`.
- Docker Compose: defines `frontend`, `backend`, `ml-service`, and `db`.
- `scripts/`: local startup helper for starting backend, frontend, and ML service outside Compose.
- `samples/`: static demo seed payloads used by backend mock seeding.
- `database/` and `docker/`: present as top-level directories during the audit but currently empty.

No tracked automated tests were found. During the audit, several `lab-telemetry` documents referenced Codex/context files that were missing from this checkout. This step creates the root `AGENTS.md`; referenced handoff files such as `docs/CODEX_CURRENT_STATUS_HANDOFF.md` and `docs/10_CODEX_NEXT_TASKS.md` remain absent unless deliberately recreated later.

## Current Implementation Status

### Implemented And Verified

- Backend routes exist for health, alert ingestion, window ingestion, alert list/detail, incident list/detail, dashboard summary, models, assets, cases, mock seed, reset, and clear-alerts compatibility.
- Backend database models exist for alerts, predictions, incidents, and incident-alert links.
- Backend normalization maps Wazuh-style alert payloads into normalized alert features.
- Backend ML client calls `/predict-event` and `/analyze-window` on the ML service.
- Backend creates prototype incidents, persists predictions, and serializes timelines, graphs, explanations, evidence, and response guidance.
- Frontend routes exist for dashboard, alerts, incidents, incident detail, assets, cases, coverage, and models.
- Frontend integrates with backend APIs through `frontend/src/api/client.ts` and React Query hooks.
- Frontend renders causal graphs with React Flow.
- ML service loads trained DoS/DDoS artifacts when available and exposes run-level and XDR-style prediction endpoints.
- Docker Compose defines the local service topology.

### Partially Implemented

- The backend has orchestration and persistence foundations, but lacks production migrations, auth/RBAC, durable official-run import, official dataset feature validation, and tracked tests.
- The frontend can display real backend records for several pages, but mock fallback is silent and can hide failed real integration.
- The frontend model page merges backend model data with mock class-level scores, feature mappings, and notes.
- Incident graph serialization exists, but graph causality is currently generated from simple model/window output and should not be treated as proven causal reasoning.
- The current trained model path is integrated for DoS-like event/window inputs and raw run rows, but the full official-run import -> trained inference -> persisted incident -> real frontend view vertical slice is not yet verified.

### Mock / Demo Only

- Backend `/api/mock/seed` seeds static demo alerts and a static multi-stage window.
- ML non-DDoS categories use keyword fallback rules, not trained non-DDoS models.
- Frontend falls back to mock data on API failure.
- Frontend coverage data is always mock data.
- The six broader frontend incident stories are demo/mock or keyword-fallback coverage unless they are backed by the trained DoS/DDoS path.
- `frontend/src/data/mockData.ts` exists locally but is ignored by `.gitignore` and was not tracked during the audit.

### Not Currently Implemented

- SOC report generation was not found as an implemented backend or frontend capability.
- Production migrations were not found.
- Authentication, authorization, and RBAC were not found.
- Tracked automated tests were not found.
- A verified official-clean-run import path into backend persistence was not found.
- A verified deterministic report API was not found.

### Uncertain

- Whether `frontend/src/data/mockData.ts` should be tracked or replaced is not determined.
- Whether the partial extracted clean release folder should be restored from the ZIP is not determined.
- Whether missing Codex/context files should be recreated as historical handoff files is not determined.

## Dataset Status

Verified official dataset facts:

- Batch ID: `training-batch-20260607T132426Z`.
- Manifest status: `completed_with_failures`.
- Planned/model-ready rows: 300.
- Completed/exported runs: 299.
- Scenario distribution: 100 `Benign`, 100 `LightDos`, 100 `AttackerHostLightDos`.
- Label distribution: 100 `Benign`, 200 `DoS_DDoS`.
- Windowed rows: 798.
- Wazuh included in windowing: true.
- Verified raw evidence metadata folders in the clean ZIP: 299.
- Incomplete run: `benign-20260607T132426Z-043`.
- The clean ZIP is the complete protected dataset release.
- The extracted clean release folder is partial and must not be presented as complete.

The current dataset is controlled, log-centric, and mainly application-layer service stress / single-source DoS. It must not be described as production-grade or complete distributed DDoS coverage.

## ML Status

### Teachers And Explainers

- EBM: teacher is `ebm_best_model.joblib`; explanation is native EBM.
- XGBoost: teacher is `xgboost_best_model.joblib`; explanation is `ebm_surrogate_for_xgboost.joblib`.
- Random Forest: teacher is `random_forest_best_model.joblib`; explanation is `ebm_surrogate_for_random_forest.joblib`.
- SVM: teacher is `svm_best_model.joblib`; explanation is `ebm_surrogate_for_svm.joblib`.
- MLP: teacher is `mlp_best_model.joblib`; explanation is `ebm_surrogate_for_mlp.joblib`.

Teacher prediction means the teacher model assigns the class. Surrogate explanation means an EBM surrogate explains a non-EBM teacher. Native EBM explanation means the EBM teacher and explanation model are the same model.

### Feature Schema

Required base features:

- `request_completed_count`
- `request_rate_per_second`
- `peak_request_rate_per_second`
- `unique_path_count`
- `repeated_path_count`
- `search_query_count`
- `avg_response_time_ms`
- `max_response_time_ms`
- `p95_response_time_ms`
- `health_check_count`
- `avg_health_check_latency_ms`
- `max_health_check_latency_ms`

Engineered features:

- `request_repeat_ratio`
- `search_request_ratio`
- `health_check_ratio`
- `latency_spread_ms`
- `p95_avg_latency_ratio`

Label mapping is provided by `ml-service/models/metadata/target_label_encoder.joblib`. Runtime metadata identifies the target as `main_label` with classes `Benign` and `DoS_DDoS`.

### Endpoint Families

- Health and model metadata: `GET /health`, `GET /models`.
- XDR event/window endpoints: `POST /predict-event`, `POST /analyze-window`.
- Raw run endpoints: `POST /predict-run`, `POST /predict-run/{model_name}`.
- CSV run endpoints: `POST /predict-run-csv`, `POST /predict-run-csv/{model_name}`.
- Legacy compatibility aliases: `POST /classify-alert`, `POST /classify-window`.

### Verified Test Metrics

From model metadata:

| Model | Test F1 | Test ROC AUC |
| --- | ---: | ---: |
| EBM | 0.9639 | 0.9975 |
| XGBoost | 0.9639 | 0.9900 |
| Random Forest | 0.9639 | 0.9813 |
| SVM | 0.9302 | 0.9863 |
| MLP | 0.8764 | 0.8675 |

Known limitation: broader non-DDoS incident categories are keyword fallback/demo behavior, not trained model coverage.

## Current Architecture

Target pipeline:

```text
Verified run or Wazuh-linked evidence
 backend evidence import
 normalization
 exact feature validation/construction
 ML-service inference
 explanation payload
 persistence
 incident creation
 evidence-grounded graph
 deterministic SOC report
 frontend investigation dashboard
```

Current implemented service boundary:

```text
frontend -> backend -> ml-service
```

The frontend must not call the ML service directly. Wazuh remains the telemetry and evidence substrate. Backend owns orchestration, persistence, incident construction, graph assembly, and SOC report generation.

## Current Main Gap

The individual components exist, but the verified vertical slice is incomplete. The missing slice is:

```text
official clean verified run
 backend import
 exact feature validation
 trained ML inference
 persisted prediction, explanation, and evidence links
 incident construction
 graph and report APIs
 real frontend incident view
```

In particular, the official dataset/evidence import, exact trained-model invocation, persisted incident/explanation, real graph/report APIs, and non-mock frontend display are not yet connected as one verified path.

## Frontend Objective

The planned showcase dashboard should present real backend incidents backed by the trained DoS/DDoS pipeline, including evidence provenance, model output, explanation features, graph, response guidance, and report-ready narrative. This is planned; it is not currently complete. Existing six-scenario frontend stories are demo/mock or keyword-fallback unless tied to the trained DoS/DDoS path.

## Important Lessons

- Do not hide failures through silent mock fallback.
- Do not overwrite analyst state during re-analysis.
- Persist multi-record operations transactionally.
- Preserve evidence provenance.
- Preserve model and schema versions.
- Distinguish teacher prediction from surrogate explanation.
- Distinguish real trained scope from mock/historical scope.
- Do not infer causality from temporal order alone.

## Immediate Milestone

```text
Official clean verified run
 backend import
 exact feature validation
 trained ML inference
 persisted prediction, explanation, and evidence links
 incident construction
 graph and report APIs
 real frontend incident view
```
