# Current Project Status

## 1. Executive Summary

This repository is a prototype Explainable XDR/SIEM platform with a FastAPI backend, React/Vite frontend, PostgreSQL persistence, and an ML service that loads trained binary DoS/DDoS models. The current trained-model scope is only `Benign` versus `DoS_DDoS`.

The broad four-class project scope remains historical/reference material. The six broader frontend incident stories are demo/mock or keyword-fallback coverage unless backed by the trained DoS/DDoS pipeline.

The official dataset is `training-batch-20260607T132426Z`: 300 planned/model-ready rows, 299 successfully exported verified runs, 100 `Benign`, 100 `LightDos`, 100 `AttackerHostLightDos`, 100 `Benign` labels, 200 `DoS_DDoS` labels, and 798 windowed rows. The incomplete run is `benign-20260607T132426Z-043`.

The complete protected release currently exists in the clean ZIP. The extracted clean release folder is partial and must not be presented as complete.

## 2. Current Implemented Scope

Implemented scope is a backend-orchestrated prototype:

- Backend alert ingestion, normalization, ML client calls, PostgreSQL persistence, incident creation, and timeline/graph serialization.
- ML service trained binary DoS/DDoS runtime for DoS-like events/windows and raw run-level rows.
- Frontend investigation UI routes and components, including React Flow graph rendering.
- Docker Compose service topology for frontend, backend, ML service, and PostgreSQL.

Not implemented as a verified end-to-end vertical slice:

- Official clean verified-run import into backend.
- Exact feature validation/construction from official evidence into trained model input.
- Persisted prediction/explanation/evidence links from official evidence.
- Evidence-grounded graph and deterministic SOC report APIs.
- Real non-mock frontend display of the official trained pipeline.

## 3. Repository Component Status

| Component | Status | Evidence | Notes |
| --- | --- | --- | --- |
| `backend/` | partially complete | `backend/app/main.py`, `backend/app/models.py`, `backend/app/services/*` | Working prototype foundation; lacks migrations, auth/RBAC, production hardening, and tracked tests. |
| `frontend/` | partially complete | `frontend/src/app/App.tsx`, `frontend/src/api/client.ts`, `frontend/src/components/CausalGraphPanel.tsx` | Routes and components exist, but fallback behavior is heavily mock-driven. |
| `ml-service/` | partially complete | `ml-service/main.py`, `ml-service/model_runtime.py`, `ml-service/models/**` | Trained DoS/DDoS runtime exists; broader classes use keyword fallback. |
| `lab-telemetry/` | partially complete | `lab-telemetry/README.md`, `lab-telemetry/scripts/**`, dataset release ZIP | Official dataset release exists; current docs include historical and missing-file references. |
| PostgreSQL | partially complete | `docker-compose.yml`, `backend/app/db.py` | Runtime database service and SQLAlchemy connection exist. |
| Docker Compose | complete | `docker-compose.yml` | Defines frontend, backend, ML service, and database services. |
| `scripts/` | partially complete | `scripts/start-local.ps1` | Local startup helper; may install deps if run without skip flags, so do not use during protected-context work. |
| `samples/` | mock/demo only | `samples/seed_alerts.json`, `samples/multi_stage_window.json` | Static demo seed inputs. |
| `database/`, `docker/` | not found | audit filesystem listing | Directories existed but contained no files during audit. |
| tracked automated tests | not found | `git ls-files` test search | No tracked project tests found. |

## 4. Dataset And Evidence Status

Verified facts:

| Item | Value |
| --- | --- |
| Official batch | `training-batch-20260607T132426Z` |
| Manifest status | `completed_with_failures` |
| Planned/model-ready rows | 300 |
| Completed/exported runs | 299 |
| Scenario distribution | 100 `Benign`, 100 `LightDos`, 100 `AttackerHostLightDos` |
| Label distribution | 100 `Benign`, 200 `DoS_DDoS` |
| Windowed rows | 798 |
| Wazuh included | yes |
| Verified evidence folders | 299 in the clean ZIP |
| Incomplete run | `benign-20260607T132426Z-043` |
| Complete release | clean ZIP |
| Extracted clean folder | partial |

Current data is controlled, log-centric, and mainly application-layer service stress / single-source DoS. It is not complete or production-grade DDoS coverage.

## 5. ML Model Status

Current trained scope:

- `Benign`
- `DoS_DDoS`

Available teacher models:

- EBM
- XGBoost
- Random Forest
- SVM
- MLP

Explanation status:

- EBM uses native EBM explanations.
- XGBoost, Random Forest, SVM, and MLP use EBM surrogates for explanation.
- Teacher prediction and surrogate explanation must be distinguished in documentation and UI.

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

Verified model metadata provides a target label encoder and metrics. Non-DDoS categories are keyword fallback/demo behavior, not trained coverage.

## 6. End-To-End Pipeline Assessment

| Stage | Status | Evidence | Missing work |
| ----- | ------ | -------- | ------------ |
| Evidence collection | complete | `lab-telemetry/README.md`, `batch-manifest.json`, clean ZIP | Maintain protected artifacts; do not rerun without explicit permission. |
| Evidence import | partially complete | `backend/app/main.py`, `samples/*.json` | Official clean verified-run import is not implemented as a verified path. |
| Normalization | partially complete | `backend/app/services/normalization_service.py` | Needs exact official evidence schema handling and validation. |
| Feature construction | partially complete | `ml-service/model_runtime.py`, dataset ZIP CSVs | Runtime official-run feature construction is not connected end-to-end. |
| ML inference | partially complete | `ml-service/main.py`, `ml-service/model_runtime.py` | Trained DoS/DDoS works for candidate/run inputs; broader classes are fallback. |
| Explanation generation | partially complete | `ml-service/model_runtime.py`, model explanation artifacts | Needs persisted official-evidence explanations and stage/evidence labels. |
| Database persistence | partially complete | `backend/app/models.py`, `backend/app/services/ingestion_service.py` | Needs migrations, transaction hardening, evidence link schema/versioning. |
| Incident creation | partially complete | `backend/app/services/ingestion_service.py` | Needs official evidence import and durable trained-model incident workflow. |
| Graph construction | partially complete | `backend/app/services/serialization.py`, `ml-service/model_runtime.py` | Current graph is generated; evidence-grounded causality is not verified. |
| SOC report generation | not found | No route or report generator found | Implement deterministic report API/output. |
| Frontend presentation | partially complete | `frontend/src/app/App.tsx`, `frontend/src/api/client.ts` | Must expose real pipeline state and not hide failures through mock fallback. |

## 7. Real Versus Mock Functionality

Real/prototype functionality:

- Backend API routes and persistence foundation.
- Backend ML client integration.
- ML DoS/DDoS trained runtime and explanation payloads.
- Frontend routes, React Query integration, charts, tables, incident detail, and React Flow graph component.

Mock/demo-only or fallback:

- `/api/mock/seed` static data.
- Frontend fallback to `mockStore` on API failure.
- Coverage page data is always mock.
- Frontend model metrics/mappings are merged from mock data.
- Six broader frontend incident stories are not six trained pipelines.
- Non-DDoS ML classes use keyword fallback.
- `frontend/src/data/mockData.ts` exists locally but is ignored and not tracked.

## 8. Historical Scope Versus Current Scope

Historical/reference scope:

- Four incident classes: Malware Attacks, Unauthorized Access, Data Breaches, Denial of Service.
- Broader project plans around multi-class SOC/XDR workflows.

Current trained scope:

- Binary `Benign` versus `DoS_DDoS`.
- Controlled application-layer DoS/service-stress logs and Wazuh-linked evidence.

Planned future capabilities:

- Explanation labels.
- Evidence role/score datasets.
- Evidence-grounded graph/report APIs.
- True multi-source DDoS support only after multiple visible source IPs are verified.
- Broader incident classes only when backed by real trained/evidence pipelines.

## 9. Documentation Discrepancies

| File | Current claim | Verified reality | Required correction |
| --- | --- | --- | --- |
| `README.md` | ML service is mock/placeholder logic today. | ML service includes trained DoS/DDoS runtime plus keyword fallback. | Update to trained DoS/DDoS runtime with fallback. |
| `frontend/README.md` | Complete six-scenario demo flows. | Six scenarios are demo/mock or keyword fallback unless tied to DoS/DDoS trained path. | Mark six-scenario scope as demo-only. |
| `lab-telemetry/README.md` | References `AGENTS.md`, Codex handoff, next-task docs. | Root `AGENTS.md` is created by this step; referenced handoff/next-task docs remain absent unless deliberately recreated later. | Remove, replace, or recreate deliberately later. |
| `ml-service/MODEL_INTEGRATION_README.md` | Includes old training-service endpoint names such as `/predict` and `/predict_csv`. | Current runtime uses `/predict-run*` endpoint families. | Separate historical training docs from current runtime docs. |
| Extracted clean dataset folder | Appears to be clean release folder. | Extracted folder is partial; ZIP contains complete package. | Do not present extracted folder as complete. |
| Clean release README | Contains unresolved `$batchId` and corrupt path characters. | Audit observed unresolved/corrupt content. | Regenerate in a future dataset-doc sync, not now. |
| Project tests | Some dependency tests exist under ignored `node_modules`. | No tracked project tests found. | Add real tracked tests later. |
| Frontend mock data | UI imports `frontend/src/data/mockData.ts`. | File is ignored and not tracked. | Decide whether to track, replace, or remove fallback later. |

## 10. Known Limitations

- Current trained model scope is binary only.
- Current dataset is controlled lab data, not production-grade DDoS evidence.
- Current DoS/service-stress data is mainly single-source.
- Mock fallback can hide real pipeline failures.
- No tracked automated tests were found.
- No production migrations were found.
- No auth/RBAC was found.
- No SOC report generation implementation was found.
- No verified official dataset/evidence import into backend was found.
- Temporal ordering alone must not be treated as proven causality.

## 11. Protected Artifacts

Do not modify without explicit permission:

- `ml-service/models/teachers/**`
- `ml-service/models/surrogates/**`
- `ml-service/models/metadata/**`
- `frontend/public/model-explanations/**`
- Official dataset release ZIP.
- Official dataset exports and verified evidence.
- `lab-telemetry/screenshots/**`
- Historical source/reference documents.

## 12. Immediate Next Milestone

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

## 13. Open Questions

- Should `frontend/src/data/mockData.ts` be tracked, replaced, or removed?
- Should the partial extracted clean release folder be restored from the ZIP or left as a partial convenience folder?
- Which missing Codex/context handoff docs should be recreated versus removed from documentation references?
- Should backend `/api/models` proxy real ML-service `/models` metadata?
- Should SOC report generation be a backend route, a frontend export, or a separate document-generation path?

## 14. Last Verified Date And Evidence Sources

Last verified by read-only repository audit: 2026-06-20.

Primary evidence sources:

- Current implementation and executable configuration.
- `docker-compose.yml`
- `backend/app/**`
- `frontend/src/**`
- `ml-service/main.py`
- `ml-service/model_runtime.py`
- `ml-service/models/metadata/**`
- Official dataset clean ZIP and extracted manifest/summary files.
- `lab-telemetry/README.md`
- `lab-telemetry/docs/00_PROJECT_CONTEXT_SUMMARY.md`
- `docs/PROJECT_STATUS_EVIDENCE.md`
