# Project Status Evidence

This matrix is the traceability anchor for `Codex.md` and `docs/00_PROJECT_CURRENT_STATUS.md`. Use it when deciding whether a statement is implemented, partially implemented, mock/demo only, not found, or uncertain.

| Claim | Status | Evidence path | Symbol, endpoint, artifact, or relevant section | Limitations |
| --- | --- | --- | --- | --- |
| Backend exposes health route. | partially complete | `backend/app/main.py` | `GET /health` | Prototype health only; no auth. |
| Backend exposes alert ingest route. | partially complete | `backend/app/main.py` | `POST /api/alerts/ingest` | Uses current alert payload, not official-run import. |
| Backend exposes window incident ingest route. | partially complete | `backend/app/main.py` | `POST /api/incidents/ingest-window` | Window comes from API payload, not verified official dataset import. |
| Backend exposes alert list/detail routes. | partially complete | `backend/app/main.py` | `GET /api/alerts`, `GET /api/alerts/{alert_id}` | Depends on database contents. |
| Backend exposes incident list/detail routes. | partially complete | `backend/app/main.py` | `GET /api/incidents`, `GET /api/incidents/{incident_id}` | Incident content reflects prototype incident creation. |
| Backend exposes dashboard summary. | partially complete | `backend/app/main.py` | `GET /api/dashboard/summary` | Derived from persisted incidents/alerts only. |
| Backend exposes model metadata route. | partially complete | `backend/app/main.py` | `GET /api/models` | Hardcoded backend model cards; does not proxy ML `/models`. |
| Backend exposes assets and cases. | partially complete | `backend/app/main.py` | `GET /api/assets`, `GET /api/cases` | Derived/prototype views from alerts/incidents. |
| Backend exposes mock seed endpoint. | mock/demo only | `backend/app/main.py`, `samples/seed_alerts.json`, `samples/multi_stage_window.json` | `POST /api/mock/seed` | Static demo payloads. |
| Backend exposes reset endpoints. | mock/demo only | `backend/app/main.py` | `DELETE /api/reset`, `DELETE /api/alerts` | Clears demo/prototype data. |
| Backend database models exist. | partially complete | `backend/app/models.py` | `Alert`, `Prediction`, `Incident`, `IncidentAlertLink` | No full migration system found. |
| Backend database session exists. | partially complete | `backend/app/db.py`, `backend/app/core/config.py` | `DATABASE_URL`, `get_db()` | PostgreSQL-specific runtime. |
| Backend schema bootstrap exists. | partially complete | `backend/app/main.py` | `run_schema_bootstrap()` | Prototype-safe DDL, not migrations. |
| Backend normalizes alert payloads. | partially complete | `backend/app/services/normalization_service.py`, `backend/app/schemas.py` | `normalize_alert()`, `NormalizedAlert` | Heuristic event-family/features; not full official evidence schema. |
| Backend calls ML service for event predictions. | partially complete | `backend/app/services/ml_client.py` | `predict_event()` -> `/predict-event` | Requires reachable ML service. |
| Backend calls ML service for window analysis. | partially complete | `backend/app/services/ml_client.py` | `analyze_window()` -> `/analyze-window` | Requires reachable ML service. |
| Backend creates single-alert incidents. | partially complete | `backend/app/services/ingestion_service.py` | `ingest_single_alert()` | Creates incident when prediction type is not `Unknown`; simple graph. |
| Backend creates window incidents. | partially complete | `backend/app/services/ingestion_service.py` | `ingest_window_incident()` | Uses ML analysis; correlation is prototype-level. |
| Backend serializes incident graph/timeline/evidence. | partially complete | `backend/app/services/serialization.py` | `serialize_incident_detail()` | Evidence/graph are generated structures, not verified causal proof. |
| Frontend routes exist. | partially complete | `frontend/src/app/App.tsx` | `/dashboard`, `/alerts`, `/incidents`, `/incidents/:id`, `/assets`, `/cases`, `/coverage`, `/models` | Route availability does not imply real backend data. |
| Frontend API client integrates with backend. | partially complete | `frontend/src/api/client.ts` | `tryFetch()`, `api.getAlerts()`, `api.getIncidents()`, etc. | Falls back silently on failure. |
| Frontend uses React Query hooks. | partially complete | `frontend/src/hooks/queries.ts` | `useAlertsQuery()`, `useIncidentDetailQuery()`, etc. | Data may be mock fallback. |
| Frontend dashboard can seed and clear demo data. | mock/demo only | `frontend/src/pages/DashboardPage.tsx`, `frontend/src/api/client.ts` | `api.seedDemoData()`, `api.clearDemoData()` | Calls mock seed/reset and also resets local mock store. |
| Frontend mock fallback exists. | mock/demo only | `frontend/src/api/client.ts` | `withFallback()` | Can hide failed real pipeline. |
| Frontend coverage page is mock-backed. | mock/demo only | `frontend/src/api/client.ts` | `api.getCoverage()` returns `mockStore.coverage` | No backend coverage route used. |
| Frontend model data is partly mock-backed. | mock/demo only | `frontend/src/api/client.ts` | `api.getModels()` merges backend data with mock metrics/mappings | Can overstate model coverage. |
| Frontend mock-data dependency is ignored/untracked. | uncertain | `.gitignore`, `frontend/src/data/mockData.ts`, `git status --ignored` audit | `.gitignore` pattern `data/` | File exists locally but was not tracked in audit. |
| Frontend renders React Flow graph. | partially complete | `frontend/src/components/CausalGraphPanel.tsx`, `frontend/package.json` | `ReactFlow`, `reactflow` dependency | Graph data quality depends on backend/ML payload. |
| ML service health route exists. | complete | `ml-service/main.py` | `GET /health` | Reports runtime model status. |
| ML service model metadata route exists. | complete | `ml-service/main.py` | `GET /models` | Backend does not currently proxy this route. |
| ML service XDR event endpoint exists. | partially complete | `ml-service/main.py` | `POST /predict-event` | Trained path only for DoS candidates; otherwise keyword fallback. |
| ML service XDR window endpoint exists. | partially complete | `ml-service/main.py` | `POST /analyze-window` | Trained path only for DoS candidates; otherwise keyword fallback/window rules. |
| ML service run row endpoints exist. | complete | `ml-service/main.py` | `POST /predict-run`, `POST /predict-run/{model_name}` | Requires required base features. |
| ML service CSV endpoints exist. | complete | `ml-service/main.py` | `POST /predict-run-csv`, `POST /predict-run-csv/{model_name}` | Requires parseable CSV with required features. |
| ML service legacy endpoints exist. | mock/demo only | `ml-service/main.py` | `POST /classify-alert`, `POST /classify-window` | Compatibility/keyword fallback behavior. |
| ML service has keyword fallback for broader classes. | mock/demo only | `ml-service/main.py` | `ATTACK_RULES`, `classify_text()` | Not trained non-DDoS coverage. |
| EBM teacher artifact exists. | complete | `ml-service/models/teachers/ebm_best_model.joblib` | model file | Protected artifact. |
| XGBoost teacher artifact exists. | complete | `ml-service/models/teachers/xgboost_best_model.joblib` | model file | Protected artifact. |
| Random Forest teacher artifact exists. | complete | `ml-service/models/teachers/random_forest_best_model.joblib` | model file | Protected artifact. |
| SVM teacher artifact exists. | complete | `ml-service/models/teachers/svm_best_model.joblib` | model file | Protected artifact. |
| MLP teacher artifact exists. | complete | `ml-service/models/teachers/mlp_best_model.joblib` | model file | Protected artifact. |
| XGBoost EBM surrogate exists. | complete | `ml-service/models/surrogates/ebm_surrogate_for_xgboost.joblib` | surrogate file | Protected artifact. |
| Random Forest EBM surrogate exists. | complete | `ml-service/models/surrogates/ebm_surrogate_for_random_forest.joblib` | surrogate file | Protected artifact. |
| SVM EBM surrogate exists. | complete | `ml-service/models/surrogates/ebm_surrogate_for_svm.joblib` | surrogate file | Protected artifact. |
| MLP EBM surrogate exists. | complete | `ml-service/models/surrogates/ebm_surrogate_for_mlp.joblib` | surrogate file | Protected artifact. |
| Native EBM explanation is used for EBM. | complete | `ml-service/model_runtime.py` | `MODEL_CONFIGS["ebm"]`, same teacher/surrogate path | Native EBM only for EBM model. |
| Surrogate explanation is used for non-EBM teachers. | complete | `ml-service/model_runtime.py` | `MODEL_CONFIGS` surrogate paths | Surrogate fidelity varies by model. |
| Model base feature schema is defined. | complete | `ml-service/model_runtime.py`, `ml-service/models/metadata/run_summary.json` | `BASE_FEATURES` | Inputs missing these columns are rejected for run endpoints. |
| Model engineered feature schema is defined. | complete | `ml-service/model_runtime.py`, `ml-service/models/metadata/run_summary.json` | `ENGINEERED_FEATURES`, `prepare_features()` | Engineered at runtime from base features. |
| Label mapping artifact exists. | complete | `ml-service/models/metadata/target_label_encoder.joblib` | target label encoder | Protected artifact. |
| Model target classes are binary. | complete | `ml-service/models/metadata/run_summary.json`, `ml-service/model_runtime.py` | `target_classes`, `POSITIVE_CLASS` | `Benign` and `DoS_DDoS` only. |
| Model metrics are available. | complete | `ml-service/models/metadata/metrics_summary.csv` | test F1/ROC AUC rows | Controlled-lab metrics; not production validation. |
| Surrogate fidelity metadata is available. | complete | `ml-service/models/metadata/surrogate_fidelity_error_report.json`, `surrogate_fidelity_error_summary.csv` | surrogate fidelity metrics | Error subsets are small/high variance. |
| Official dataset batch ID is verified. | complete | `lab-telemetry/exports/dataset-releases/coding-fest-2026-xdr-dataset-training-batch-20260607T132426Z-clean/batch-manifest/batch-manifest.json` | `batch_id` | Extracted manifest exists. |
| Official manifest status is completed with failures. | complete | same manifest | `status: completed_with_failures` | One failed run. |
| Planned/model-ready row count is 300. | complete | clean ZIP, `quality-summary.json`, model metadata | model-ready CSV rows, `total_runs`, `raw_shape` | Model-ready CSV is in ZIP; extracted folder is partial. |
| Completed/exported run count is 299. | complete | `batch-manifest.json`, clean ZIP | 299 completed/exported, 299 metadata files | Incomplete run excluded from raw evidence. |
| Scenario counts are verified. | complete | `quality-summary.json`, `quality-summary.csv` | 100 each for `Benign`, `LightDos`, `AttackerHostLightDos` | Quality summary extracted. |
| Label distribution is verified. | complete | `quality-summary.json`, docs audit | 100 `Benign`, 200 `DoS_DDoS` | CSV column naming used `label` in extracted quality summary. |
| Windowed row count is 798. | complete | clean ZIP, `window-build-summary.json` | `row_count: 798`, windows CSV rows | Windows CSV is in ZIP; extracted folder is partial. |
| Wazuh inclusion is verified. | complete | `window-build-summary.json`, lab docs | `include_wazuh: true` | Wazuh is evidence context, not ground-truth labels. |
| Incomplete run is verified. | complete | `batch-manifest.json`, `quality-summary.json` | `benign-20260607T132426Z-043` | Verification failed; export not run. |
| Complete dataset release exists as ZIP. | complete | `lab-telemetry/exports/dataset-releases/coding-fest-2026-xdr-dataset-training-batch-20260607T132426Z-clean.zip` | clean release ZIP | Protected artifact. |
| Extracted clean release folder is partial. | complete | `lab-telemetry/exports/dataset-releases/coding-fest-2026-xdr-dataset-training-batch-20260607T132426Z-clean/` | only manifest/summary/docs subset observed | Do not present as complete. |
| Clean release README has unresolved/corrupt content. | complete | `lab-telemetry/exports/dataset-releases/...-clean/README.md` | unresolved `$batchId`, corrupt path characters observed | Historical/generated artifact; do not modify in this step. |
| Docker services are defined. | complete | `docker-compose.yml` | `frontend`, `backend`, `ml-service`, `db` | Runtime health not verified in this context-file step. |
| Environment example exists. | complete | `.env.example` | `DATABASE_URL`, `ML_SERVICE_URL`, seed paths, `VITE_API_BASE_URL` | Example only. |
| No tracked automated tests were found. | not found | `git ls-files` audit | no tracked `test`, `tests`, `.test.`, `.spec.` matches | Ignored dependency tests under `node_modules` are not project tests. |
| SOC report generation was not found. | not found | backend/frontend route and symbol audit | no report route/generator found | Planned backend-owned capability. |
| Official-run import support is incomplete. | partially complete | `backend/app/main.py`, `samples/*.json`, dataset artifacts | ingest endpoints accept alert/window payloads; no official clean verified-run importer | Main vertical-slice gap. |
| Historical four-class scope exists in docs. | complete | `lab-telemetry/docs/00_PROJECT_CONTEXT_SUMMARY.md`, `lab-telemetry/docs/02_official_project_proposal.md` | Malware, Unauthorized Access, Data Breaches, Denial of Service | Historical/reference, not current trained scope. |
| Six frontend incident stories are demo/mock unless trained path backs them. | mock/demo only | `frontend/README.md`, `frontend/src/data/mockData.ts`, `ml-service/main.py` | six scenarios, mock data, keyword fallback | Not six trained end-to-end pipelines. |
| Several referenced Codex/context handoff files were missing. | not found | `lab-telemetry/README.md`, audit file search | references include `docs/CODEX_CURRENT_STATUS_HANDOFF.md`, `docs/10_CODEX_NEXT_TASKS.md`; root `AGENTS.md` is created by this step | Remaining handoff files should be recreated or references removed deliberately later. |
| Root README has stale ML mock-only claim. | partially complete | `README.md`, `ml-service/main.py`, `ml-service/model_runtime.py` | README says mock/placeholder; code loads trained runtime | Documentation discrepancy. |
| Frontend README overstates six-scenario completeness. | partially complete | `frontend/README.md`, `frontend/src/api/client.ts`, `frontend/src/data/mockData.ts` | complete demo flows vs mock fallback | Documentation discrepancy. |
| ML integration README has outdated endpoint references. | partially complete | `ml-service/MODEL_INTEGRATION_README.md`, `ml-service/main.py` | old `/predict` docs vs current `/predict-run*` routes | Documentation discrepancy. |
