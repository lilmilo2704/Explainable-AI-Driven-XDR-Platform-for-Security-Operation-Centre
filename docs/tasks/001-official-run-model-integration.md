# 001 - Official Run Model Integration Plan

## 1. Goal And Non-Goals

Goal: implement the first real backend-owned integration slice from the protected official release ZIP through raw-evidence parsing, exact feature reconstruction, trained EBM inference, persistence, incident linking, and later investigation storyline/report APIs.

Required pipeline:

```text
Protected official release ZIP
 select and verify run
 inventory raw evidence
 parse raw evidence
 normalize canonical events
 reconstruct exact base features
 compare reconstructed features with official feature row
 record parity result
 call trained EBM
 persist run, evidence, features, prediction and explanation
 create or link incident
 later build investigation storyline and deterministic report
```

Non-goals:

- No runtime implementation in this planning step.
- No model retraining, model replacement, or artifact modification.
- No keyword or mock fallback for the official trained pipeline.
- No claim of complete, distributed, real-world, or production-grade DDoS coverage.
- No frontend implementation in Phase 1, except defining backend API contracts.
- No LLM-generated source of truth for reports.
- No extraction, repair, alteration, or rewrite of the official release ZIP or extracted release folder.

Current trained scope remains binary: `Benign` versus `DoS_DDoS`.

## 2. Selected Raw-Evidence Approach

Approved input: raw verified logs only.

The backend must reconstruct the trained model's required base features from raw verified evidence in the protected official release ZIP. The official feature CSV may be read only as a validation oracle for training-serving parity. It must not be used as the operational model input.

Initial model:

- Use `ebm`.
- Call the real trained run-level ML endpoint: `POST /predict-run/ebm`.
- Use native EBM explanations.
- Do not call `/predict-event` or `/analyze-window` for this milestone because those paths may estimate features from text and can fall back to keyword behavior.

Initial attack run candidate:

- Preferred run: `attackerhostlightdos-20260607T132426Z-201`.
- If it fails any verification requirement, select the next complete `AttackerHostLightDos` run in manifest order and document the rejection reason.
- Plan a later benign comparison run in Phase 3.

## 3. Run-Verification Procedure

For a requested `{ release_id, run_id, model_name }`, the backend verifies:

1. `release_id` resolves through a server-side allowlist to the protected clean ZIP.
2. `model_name` is allowlisted for Phase 1 as `ebm`.
3. `run_id` matches the strict expected pattern for official run IDs.
4. A matching manifest entry exists in `batch-manifest/batch-manifest.json`.
5. Manifest entry status is complete:
   - `status == "completed"`
   - `verification_status == "passed"`
   - `export_status == "exported"`
6. The run is not the incomplete run `benign-20260607T132426Z-043`.
7. Official feature row exists in `ml-features/training-batch-20260607T132426Z-features.csv`.
8. Raw verified evidence folder exists in the ZIP under `raw-evidence/verified-runs/{run_id}/`.
9. Required application or nginx evidence exists:
   - `webapp-slice.log` or `nginx-access-slice.log`.
10. Wazuh evidence exists where expected:
    - `wazuh-evidence-summary.json`
    - `wazuh-alerts-slice.json` and/or `wazuh-archives-slice.json`
11. Run metadata confirms clean supervised candidate status, either directly from metadata/feature fields or by cross-checking the official feature oracle row's `is_clean_supervised_training_candidate`.
12. Required files are parseable within configured size and format limits.

If `attackerhostlightdos-20260607T132426Z-201` does not satisfy all checks, selection advances to the next complete `AttackerHostLightDos` run. The import response and logs should include a structured rejection record for the skipped candidate, without exposing absolute paths or raw logs.

## 4. ZIP Security Model

Dataset access:

- API accepts only:
  - `release_id`
  - `run_id`
  - `model_name`
- API must not accept:
  - arbitrary files
  - directories
  - ZIP paths
  - absolute paths
  - client-provided evidence roots

Server-side release allowlist:

- Example release ID: `coding-fest-2026-clean`.
- Maps internally to the protected clean ZIP:
  `lab-telemetry/exports/dataset-releases/coding-fest-2026-xdr-dataset-training-batch-20260607T132426Z-clean.zip`.

Safe ZIP handling:

- Open the protected ZIP read-only.
- Never extract over the official release folder.
- Never repair, rewrite, or alter the ZIP.
- Use allowed prefixes only:
  - `coding-fest-2026-xdr-dataset-training-batch-20260607T132426Z-clean/batch-manifest/`
  - `coding-fest-2026-xdr-dataset-training-batch-20260607T132426Z-clean/ml-features/`
  - `coding-fest-2026-xdr-dataset-training-batch-20260607T132426Z-clean/raw-evidence/verified-runs/{run_id}/`
- Normalize separators to `/` before validation.
- Reject absolute paths, drive letters, empty path segments, and `..`.
- Enforce a file type allowlist:
  - `.json`
  - `.csv`
  - `.log`
  - `.md` only for inventory/reference, not model input.
- Enforce per-entry size limits and total read limits.
- Hash every evidence entry that is inventoried or parsed.

## 5. Raw Evidence Types And Parser Responsibilities

Required parser inputs for Phase 1:

- `metadata.json`: run ID, scenario, label, target window, start/end timestamps, generator metadata, expected sources.
- `manifest.json`: run-local artifact inventory and validation context.
- `webapp-slice.log`: application request/completion records when available.
- `nginx-access-slice.log`: HTTP access records and request paths when available.
- `wazuh-evidence-summary.json`: Wazuh evidence counts and expected Wazuh context.
- `wazuh-alerts-slice.json`: Wazuh alert context when present.
- `wazuh-archives-slice.json`: Wazuh archive context when present.

Parser responsibilities:

- Parse each supported file into canonical events.
- Record parse warnings by file and line/record number.
- Reject required files that are absent, oversize, malformed, or unsupported.
- Treat Wazuh as evidence context, not ground-truth labels.
- Never return full raw logs by default.
- Store logical ZIP-relative paths and hashes, not local absolute paths.

Unsupported evidence:

- May be inventoried as an `EvidenceReference`.
- Must not contribute to feature reconstruction until a parser and derivation rule exist.

## 6. Canonical Event Schema

Canonical event records should be backend-owned and versioned:

```json
{
  "schema_version": "canonical-event.v1",
  "event_id": "stable per run and source record",
  "release_id": "coding-fest-2026-clean",
  "batch_id": "training-batch-20260607T132426Z",
  "run_id": "attackerhostlightdos-20260607T132426Z-201",
  "source_type": "webapp | nginx | wazuh_alert | wazuh_archive | metadata",
  "source_ref": {
    "zip_entry": "raw-evidence/verified-runs/.../webapp-slice.log",
    "record_id": "line:42",
    "sha256": "entry or record hash"
  },
  "timestamp": "ISO-8601 or null",
  "event_type": "request_completed | health_check | search_query | wazuh_observation | run_metadata",
  "http": {
    "method": "GET",
    "path": "/search",
    "query": "q=example",
    "status": 200,
    "response_time_ms": 12.3
  },
  "actor": {
    "source_ip": "redacted or null"
  },
  "raw_summary": "sanitized short summary",
  "parse_warnings": []
}
```

Canonical request events must preserve enough data to reconstruct the exact 12 base features without reading the official feature row as input.

## 7. Exact Feature Derivation Table

Feature schema version: `run-level-base-features.v1`.

General parity rules:

- Compare reconstructed features to the official oracle row after reconstruction.
- Integer/count features must match exactly.
- Rate and latency features should match the oracle after applying the same rounding precision observed in the official feature row. Initial tolerance is `<= 0.001` for values represented to three decimals and exact equality for values represented as integers.
- Any broader tolerance requires a documented parser or rounding cause and should block Phase 1D until approved.
- Missing required source data blocks EBM inference.

| Feature | Source log/event type | Extraction rule | Aggregation rule | Missing-data behavior | Unit | Parity comparison |
| --- | --- | --- | --- | --- | --- | --- |
| `request_completed_count` | Application `request_completed` events preferred; nginx access records as cross-check or fallback when application events are absent. | Select completed HTTP request events inside the verified run time window. Exclude unsupported/non-request records. | Count canonical `request_completed` events. | Block if neither application nor nginx request evidence is parseable. | count | Exact integer match. |
| `request_rate_per_second` | Same canonical completed request events plus run duration from metadata or first/last request timestamps according to verified training rule. | Use the same run duration basis used by dataset generation; parser records which basis was used. | `request_completed_count / duration_seconds`, rounded to oracle precision. | Block if duration cannot be reconstructed or is non-positive. | requests/second | `<= 0.001` unless oracle precision proves stricter. |
| `peak_request_rate_per_second` | Canonical completed request timestamps. | Bucket completed requests into the training window interval used by the official builder, initially one-second buckets unless verified otherwise. | Maximum bucketed request rate. | Block if timestamps are missing or bucket rule cannot be verified. | requests/second | Exact if integer-valued; otherwise `<= 0.001`. |
| `unique_path_count` | Application request path or nginx request URI. | Normalize path by removing scheme/host/query and preserving route path according to training parser. | Count distinct normalized paths among completed requests. | Block if no request paths are parseable. | count | Exact integer match. |
| `repeated_path_count` | Same request path events. | Use normalized paths. | `request_completed_count - unique_path_count`, matching observed oracle behavior. | Block if either count cannot be reconstructed. | count | Exact integer match. |
| `search_query_count` | Application request events or nginx request URI. | Count completed requests whose normalized path/query matches the training definition of search/query activity. | Sum matching events. | Use `0` only when request evidence is parseable and no search/query events match; otherwise block. | count | Exact integer match. |
| `avg_response_time_ms` | Application response duration preferred; nginx request time/upstream time if training parser used nginx. | Extract response latency per completed request in milliseconds. | Arithmetic mean over request latencies. | Block if no latency source is parseable. | milliseconds | `<= 0.001` or exact after oracle rounding. |
| `max_response_time_ms` | Same request latency events. | Extract response latency per completed request in milliseconds. | Maximum latency. | Block if no latency source is parseable. | milliseconds | `<= 0.001` or exact after oracle rounding. |
| `p95_response_time_ms` | Same request latency events. | Extract response latency per completed request in milliseconds. | 95th percentile using the same percentile method as training. Initial parser must verify method against oracle before acceptance. | Block if percentile method cannot be matched. | milliseconds | `<= 0.001` after matching method. |
| `health_check_count` | Application or nginx request path events. | Count completed requests whose normalized path matches health-check endpoints under the training definition. | Sum matching health-check events. | Use `0` only when request evidence is parseable and no health-check events match; otherwise block. | count | Exact integer match. |
| `avg_health_check_latency_ms` | Health-check request latency events. | Extract latency for requests counted by `health_check_count`. | Arithmetic mean over health-check latencies; if count is `0`, value must be `0`. | If health checks exist but latency is missing, block. If count is `0`, use `0`. | milliseconds | `<= 0.001` or exact after oracle rounding. |
| `max_health_check_latency_ms` | Health-check request latency events. | Extract latency for requests counted by `health_check_count`. | Maximum health-check latency; if count is `0`, value must be `0`. | If health checks exist but latency is missing, block. If count is `0`, use `0`. | milliseconds | `<= 0.001` or exact after oracle rounding. |

The feature extractor must also record:

- source events used for each feature
- extraction rule ID
- aggregation rule ID
- parser version
- warnings
- reconstructed feature hash
- official oracle feature hash
- per-feature parity result

## 8. Parity-Validation Strategy

Parity validation compares raw-evidence-reconstructed features to the official feature row for the same `run_id`.

The official feature CSV may be read for:

- locating the oracle row
- confirming clean supervised candidate status
- comparing reconstructed values
- recording parity status

The official feature CSV must not be used to populate the ML request body.

Parity result states:

- `passed`: all required features match exact/tolerance rules.
- `failed`: at least one required feature mismatch exceeds rule.
- `blocked`: required evidence is missing, unsafe, unparsable, or unsupported.

Phase 1D EBM inference is blocked unless parity is `passed`.

Feature parity state should be stored either in `OfficialRunImport` or a dedicated versioned feature-extraction record. Recommended: add a dedicated `RunFeatureExtraction` entity so extractor versions and parity attempts can be tracked without mutating the import identity.

## 9. Alembic Migration Plan

Use Alembic for new schema changes.

Planned migration setup:

1. Add Alembic configuration under backend ownership.
2. Baseline current SQLAlchemy models carefully without dropping existing prototype tables.
3. Add migration for new official-run entities and constraints.
4. Keep prototype bootstrap DDL for existing local compatibility only until migration ownership is fully decided.
5. Do not create or run migrations in this planning step.

Migration must add:

- `official_run_imports`
- `evidence_references`
- `run_feature_extractions`
- `run_predictions`
- `incident_run_links`
- indexes and unique constraints listed below

## 10. Entities And Uniqueness Constraints

`OfficialRunImport`:

- `id`
- `release_id`
- `batch_id`
- `run_id`
- `scenario`
- `source_label`
- `manifest_status`
- `verification_status`
- `export_status`
- `canonical_evidence_manifest_hash`
- `selected_model_name`
- `import_status`
- `failure_reason`
- `created_at`
- `updated_at`

Unique:

- `(release_id, run_id)`

`EvidenceReference`:

- `id`
- `run_import_id`
- `evidence_type`
- `source`
- `logical_zip_path`
- `record_locator`
- `sha256`
- `byte_size`
- `timestamp_start`
- `timestamp_end`
- `sanitized_summary`
- `parse_status`
- `parse_warnings`

Unique:

- `(run_import_id, logical_zip_path, record_locator)`

`RunFeatureExtraction`:

- `id`
- `run_import_id`
- `feature_schema_version`
- `extractor_name`
- `extractor_version`
- `base_features`
- `feature_sources`
- `reconstructed_feature_hash`
- `official_oracle_feature_hash`
- `parity_status`
- `parity_results`
- `created_at`

Unique:

- `(run_import_id, feature_schema_version, extractor_version, reconstructed_feature_hash)`

`RunPrediction`:

- `id`
- `run_import_id`
- `feature_extraction_id`
- `model_name`
- `model_version`
- `ml_endpoint`
- `teacher_model`
- `teacher_predicted_label`
- `teacher_predicted_class_id`
- `teacher_probabilities`
- `explanation_model`
- `explanation_model_type`
- `surrogate_predicted_label`
- `surrogate_predicted_class_id`
- `teacher_surrogate_match`
- `explanation_features`
- `processed_features`
- `raw_ml_response_sanitized`
- `created_at`

Unique:

- `(run_import_id, model_name, model_version, canonical_evidence_manifest_hash, reconstructed_feature_hash)`

`IncidentRunLink`:

- `id`
- `incident_id`
- `run_import_id`
- `run_prediction_id`
- `link_reason`
- `created_at`

Unique:

- `(incident_id, run_import_id)`
- `(run_prediction_id)`

## 11. API Contracts

### Import/Replay

`POST /api/official-runs/import`

Request:

```json
{
  "release_id": "coding-fest-2026-clean",
  "run_id": "attackerhostlightdos-20260607T132426Z-201",
  "model_name": "ebm"
}
```

Response on created/existing:

```json
{
  "pipeline_state": "real_trained_pipeline",
  "replay_status": "created",
  "run_import": {
    "id": 1,
    "release_id": "coding-fest-2026-clean",
    "batch_id": "training-batch-20260607T132426Z",
    "run_id": "attackerhostlightdos-20260607T132426Z-201",
    "scenario": "AttackerHostLightDos",
    "source_label": "DoS_DDoS",
    "import_status": "completed"
  },
  "feature_extraction": {
    "feature_schema_version": "run-level-base-features.v1",
    "extractor_version": "raw-evidence-feature-extractor.v1",
    "parity_status": "passed",
    "base_features": {}
  },
  "prediction": {
    "model_name": "ebm",
    "model_version": "xdr-run-level-dos-ebm-surrogate-v1",
    "teacher_predicted_label": "DoS_DDoS",
    "teacher_probabilities": {},
    "explanation_model_type": "native_ebm",
    "explanation_features": []
  },
  "incident_id": "INC-000001",
  "evidence_references": [],
  "graph_url": "/api/incidents/INC-000001/storyline",
  "report_url": "/api/incidents/INC-000001/report"
}
```

Structured ML failure response:

```json
{
  "error": {
    "code": "ml_service_unavailable",
    "message": "Trained EBM inference failed.",
    "pipeline_state": "failed_real_trained_pipeline",
    "fallback_used": false,
    "retryable": true
  }
}
```

### Run Lookup

`GET /api/official-runs/{run_id}?release_id=coding-fest-2026-clean`

Returns import state, feature parity state, prediction state, evidence references, and linked incident.

### Storyline

`GET /api/incidents/{incident_id}/storyline`

Returns an investigation storyline/evidence graph. Do not call it proven causality.

### Report

`GET /api/incidents/{incident_id}/report`

Returns deterministic structured report JSON.

Endpoint protection is unresolved and awaiting final approval. Recommended initial design:

- endpoint enabled only when a demo-mode environment flag is true
- require a server-side admin/demo token
- allowlisted releases only

## 12. Transaction Boundaries

Do not hold a database transaction while streaming ZIP entries or calling ML.

Recommended flow:

1. Validate request shape, release allowlist, run ID, and model name.
2. Read and validate required ZIP entries within bounded limits.
3. Parse raw evidence into canonical events.
4. Reconstruct base features.
5. Read official feature row as validation oracle only.
6. Record parity candidate in memory.
7. If parity passes, call `POST /predict-run/ebm`.
8. Open one DB transaction.
9. Upsert or create:
   - `OfficialRunImport`
   - `EvidenceReference`
   - `RunFeatureExtraction`
   - `RunPrediction`
   - `Incident`
   - `IncidentRunLink`
10. Commit once.

Rollback all durable records from the attempt if DB persistence fails.

## 13. Idempotency Behavior

For the same:

- release ID
- run ID
- model name
- model version
- raw-evidence hash or canonical evidence manifest hash
- reconstructed feature hash

return the existing result.

If the same run is encountered with changed model version, evidence hash, or reconstructed feature hash, return `409 Conflict` for this milestone.

Do not create duplicate incidents, evidence references, feature extractions, or predictions.

## 14. ML Failure Behavior

Official trained pipeline failure rules:

- no keyword fallback
- no mock fallback
- no partial incident
- no prediction record
- return explicit `502` with structured error

ML response validation must confirm:

- `model_name == "ebm"`
- model version is present
- teacher prediction fields are present
- native EBM explanation fields are present
- required processed features are present
- classes remain `Benign` and `DoS_DDoS`

## 15. Evidence-Redaction Behavior

Phase 1 responses may include:

- evidence type
- logical ZIP-relative path
- source
- timestamp or timestamp range where available
- hash
- byte size
- sanitized summary

Phase 1 responses must not expose:

- absolute local paths
- complete raw logs
- unredacted Wazuh archives
- secrets or credentials
- arbitrary raw payloads by default

Plan a controlled evidence-detail endpoint for a later phase with explicit redaction, authorization/demo guard, and size limits.

## 16. Investigation Storyline Schema

Use terminology:

- `investigation_storyline`, or
- `evidence_graph`

Do not describe it as proven causal reasoning.

Node kinds:

- `observed_evidence`
- `derived_feature`
- `model_prediction`
- `explanation_contribution`
- `incident`
- `analyst_recommendation`

Edge kinds:

- `contains_evidence`
- `parsed_from`
- `derived_from`
- `input_to_prediction`
- `explained_by`
- `feature_contributed_to_prediction`
- `supports_incident`
- `recommends_action`

Every node and edge must include provenance or an explicit derivation rule.

Top-level shape:

```json
{
  "schema_version": "evidence-graph.v1",
  "scope": {
    "trained_classes": ["Benign", "DoS_DDoS"],
    "dataset_scope": "controlled log-centric application-layer service stress",
    "causality_warning": "Edges do not prove causality unless an explicit derivation rule says so."
  },
  "nodes": [],
  "edges": []
}
```

## 17. Deterministic Report Schema

The first report is deterministic structured JSON generated from validated evidence, reconstructed features, model output, and fixed rules.

Required fields:

- `schema_version`
- `report_id`
- `incident_id`
- `release_id`
- `run_id`
- `scope_statement`
- `data_limitations`
- `evidence_summary`
- `reconstructed_features`
- `feature_parity`
- `model`
- `teacher_prediction`
- `native_ebm_explanation`
- `top_features`
- `investigation_storyline_summary`
- `recommended_actions`
- `generated_at`

Report rules:

- Sort arrays deterministically.
- Use stable IDs.
- Use fixed text templates.
- Do not use LLM output as source of truth.
- Optional LLM narrative may be added later, clearly marked as generated.

## 18. Test Matrix

Phase 1A tests:

- allowlisted release resolves to known ZIP
- unsafe release ID rejected
- unsafe run IDs rejected
- selected run has matching manifest entry
- incomplete run `benign-20260607T132426Z-043` rejected
- missing raw-evidence folder rejected
- ZIP entry traversal rejected
- oversize entry rejected

Phase 1B tests:

- parse `metadata.json`
- parse `manifest.json`
- parse `webapp-slice.log`
- parse `nginx-access-slice.log`
- parse Wazuh summary/alerts/archives
- unsupported evidence is inventoried with warnings, not used for features

Phase 1C tests:

- reconstruct all 12 base features
- compare each feature to official oracle row
- exact integer parity for count features
- strict numeric parity for rate/latency features
- block inference on parity failure
- block inference on missing required evidence

Phase 1D tests:

- backend calls `/predict-run/ebm`
- no keyword/mock fallback
- native EBM explanation preserved
- DB transaction creates all records once
- DB rollback on persistence failure
- idempotent replay returns existing result
- changed evidence/model/feature hash returns `409`
- ML unavailable returns structured `502` and creates no incident/prediction

Phase 2 tests:

- storyline graph has required node/edge kinds
- every edge has provenance or derivation rule
- no causal wording from temporal order alone
- deterministic report stable across repeated calls

Validation commands after implementation should include:

```powershell
python -m compileall backend/app ml-service
cd frontend; npm run build
cd frontend; npm run lint
docker compose up --build -d db ml-service backend
Invoke-RestMethod http://localhost:5000/health
Invoke-RestMethod http://localhost:8000/health
```

Add backend/ML pytest commands once the test harness is introduced.

## 19. Phased Implementation

### Phase 1A - Release And Run Verification

- Configure allowlisted release.
- Safely inspect ZIP.
- Validate selected run.
- Build evidence inventory.
- Create tests for missing, incomplete, and unsafe runs.

### Phase 1B - Raw-Evidence Parsing

- Parse required nginx/application/Wazuh evidence.
- Normalize canonical event structures.
- Record parse warnings and unsupported evidence.

### Phase 1C - Feature Reconstruction And Parity

- Produce exact 12-feature vector.
- Compare with official feature row.
- Document mismatches.
- Block EBM inference if required-feature parity is not acceptable.

### Phase 1D - EBM Inference And Persistence

- Call `/predict-run/ebm`.
- Persist run, evidence references, reconstructed features, model version, prediction, and native explanation.
- Link or create incident transactionally.
- Enforce idempotency.
- Return explicit errors.

### Phase 2 - Investigation Storyline And Deterministic Report

- Add evidence graph/storyline API.
- Add deterministic report API.
- No LLM dependency.

### Phase 3 - Benign Comparison

- Select and validate one complete benign run.
- Run the same raw-log pipeline.
- Verify the system distinguishes baseline from attack behavior.

### Phase 4 - Live Monitoring Adaptation

- Replace ZIP input with continuous Wazuh/application events.
- Reuse the same canonical event and feature extraction logic.
- Introduce rolling or tumbling windows.
- Perform repeated EBM inference.
- Correlate suspicious windows into active incidents.

## 20. Path From Replay To Continuous Live Monitoring

The replay importer should not become a one-off parser. It should establish reusable backend components:

- canonical event schema
- raw evidence parsers
- feature extraction rules
- parity validation against official training artifacts
- EBM inference client
- incident linking logic

For live monitoring, replace the protected ZIP reader with bounded event ingestion from Wazuh/application sources, then reuse canonical normalization and feature extraction over rolling or tumbling windows. Live monitoring must preserve the same trained scope limitation until new validated models and datasets exist.

## 21. Definition Of Done

The milestone is done when:

- The backend can select and verify one complete official `AttackerHostLightDos` run from the protected ZIP.
- Raw verified evidence is parsed into canonical events.
- All 12 required base features are reconstructed from raw evidence.
- Reconstructed features pass strict parity validation against the official feature oracle row.
- Backend calls `POST /predict-run/ebm`.
- Native EBM teacher prediction and explanation are persisted separately and accurately.
- Official run import, evidence references, feature extraction, prediction, incident link, and idempotency keys are persisted through Alembic-managed schema.
- Replaying the same run returns existing records without duplicates.
- Changed model/evidence/feature hash returns `409 Conflict`.
- ML failure returns structured `502` with no fallback and no partial incident/prediction.
- Phase 1 responses expose sanitized evidence references only.
- Protected artifact paths remain unchanged.
- Tests cover run verification, ZIP safety, parsing, feature parity, ML contract, transaction rollback, idempotency, and error behavior.
- Phase 2 plan remains ready for investigation storyline and deterministic report APIs.
