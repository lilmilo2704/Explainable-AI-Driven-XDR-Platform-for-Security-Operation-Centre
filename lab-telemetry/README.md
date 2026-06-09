# Coding Fest 2026 XDR Lab Telemetry Toolkit

This repository supports the Coding Fest 2026 Explainable AI-Driven XDR/SIEM lab by automating health checks, controlled telemetry generation, verification, verified-run export, and Wazuh-linked evidence export.

The main product is an incident-centric SOC/XDR prototype. This toolkit is only the local automation layer used to generate and validate lab evidence.

## Current Status

The project has narrowed into a log-centric, Wazuh-linked XDR dataset and prototype pipeline for detecting and explaining application-layer DoS/DDoS/service-stress incidents. The strongest current framing is:

```text
A log-centric, Wazuh-linked XDR dataset and prototype pipeline for detecting and explaining application-layer DoS/DDoS/service-stress incidents using server-side logs, web application logs, nginx logs, Wazuh archives, Wazuh alerts, and windowed behaviour features.
```

The current focus is not broad multi-incident detection. It is application-layer DoS/service-stress evidence, Wazuh-linked raw evidence, windowed ML-ready features, explainable incident storyline support, and future stage/evidence explanation models.

Current high-level labels:

- `Benign`
- `DoS_DDoS`

Scenario meanings:

- `Benign` = normal lab activity.
- `LightDos` = controlled script-generated light service-stress traffic.
- `AttackerHostLightDos` = Windows-host single-source HTTP service-stress / DoS traffic.

Important limitation: the current DoS data is mostly controlled application-layer single-source DoS/service-stress, not full distributed DDoS. Do not claim complete DDoS coverage until victim logs show multiple visible source IPs from multi-source runs.

Next work is the explanation layer: stage labels, evidence roles, evidence scores, model-ready explanation datasets, quality reports, and eventually an explanation-enriched release.

Read first for current context:

- `docs/CODEX_CURRENT_STATUS_HANDOFF.md`
- `docs/10_CODEX_NEXT_TASKS.md`

## Current official dataset

Official batch ID:

```text
training-batch-20260607T132426Z
```

Official clean release package:

```text
exports\dataset-releases\coding-fest-2026-xdr-dataset-training-batch-20260607T132426Z-clean\
exports\dataset-releases\coding-fest-2026-xdr-dataset-training-batch-20260607T132426Z-clean.zip
```

Known dataset facts:

| Item | Count / status |
|---|---:|
| Tabular runs | 300 |
| `Benign` runs | 100 |
| `LightDos` runs | 100 |
| `AttackerHostLightDos` runs | 100 |
| `DoS_DDoS` labelled runs | 200 |
| Windowed rows | 798 |
| Model-ready run-level rows | 300 |
| Raw verified-run evidence folders | 299 |

`benign-20260607T132426Z-043` is the known incomplete run. It failed verification/export and is intentionally missing from raw evidence, so the clean release correctly has 300 tabular rows but 299 raw evidence folders.

For clean supervised training, use:

```text
is_clean_supervised_training_candidate == True
```

The clean release removed laptop-specific absolute paths such as `C:\D\xdr-lab-telemetry` and excluded old/raw accidental folders.

## Current lab targets

- Auth Server: dynamically resolved Multipass `auth-server`, port `8000`
- Web Server through nginx: dynamically resolved Multipass `web-server`, port `80`
- Database Server: `db-server`, PostgreSQL database `xdr_lab`
- Wazuh all-in-one server: `wazuh-server`

The scripts resolve current bridged DHCP addresses. Historical IPs should not be treated as fixed.

## Pipeline status

Completed:

- DB/Auth/Web Multipass lab foundation
- Auth API with JSON logs
- Web app with search/login/admin routes and JSON logs
- nginx reverse proxy
- linked Web/Auth evidence
- health/start script
- dataset-quality controlled telemetry generator
- metadata-driven log verifier
- local log cache helper for safer Windows verification
- verified-run raw evidence exporter
- dataset batch runner for repeatable multi-run collection
- local dataset factory stable for the four current lab-supported scenarios
- scenario-default actor profile mode validated with a completed 4-run batch
- Wazuh all-in-one server and active agents on Auth/Web/DB
- Wazuh archive logging and lab localfile collection
- stable Wazuh evidence export using local transferred cache files
- Wazuh evidence export bug fixed for compressed `.json.gz` files and local-timezone date candidates
- fast Wazuh batch exporter created and used successfully
- service-impact `request_completed` web logging and LightDos field checks
- configurable batch inter-run delay to reduce evidence-window overlap
- completed six-run Benign/LightDos reference batch with 30-second separation and Wazuh evidence export
- completed earlier 90-run v1 dataset from `training-batch-20260606T203336Z`
- completed official 300-row dataset from `training-batch-20260607T132426Z`
- dataset quality summary builder
- ML feature table builder
- raw-content ML feature export
- windowed dataset builder
- model-ready run-level dataset builder
- clean portable release packaging

Next:

- build the explanation-labelling layer without modifying existing dataset outputs
- create stage labels, evidence roles, evidence scores, label summaries, and label guides
- create model-ready explanation datasets and explanation label quality reports
- package an explanation-enriched release after labels are built and checked
- add true multi-source support only when multiple visible source IPs can be produced in victim logs

## Current evidence sources

Each complete verified run folder may contain:

- `metadata.json`
- `manifest.json`
- `README.md`
- `auth-slice.log`
- `webapp-slice.log`
- `nginx-access-slice.log`
- `wazuh-archives-slice.json`
- `wazuh-alerts-slice.json`
- `wazuh-evidence-summary.json`

The most important evidence for DoS/service-stress explanation is:

- nginx access logs
- webapp structured JSON logs
- Wazuh archive events mirroring nginx/webapp evidence
- Wazuh alert context when relevant
- request counts
- source IP concentration
- `response_time_ms` / `request_duration_ms`
- status codes
- health-check latency/failure if available
- nginx errors if available

## Explanation-layer direction

The next major project direction is to enrich the dataset with weak explanation labels. These labels should support stage classification, evidence attribution, an incident storyline graph, and SOC-style report generation.

New labels:

- `stage_label`
- `evidence_role`
- `evidence_score`

Stage labels:

- `baseline`
- `burst_onset`
- `sustained_pressure`
- `service_stress`
- `service_degradation`
- `recovery`
- `unclear`

Evidence roles:

- `baseline_sample`
- `representative_burst_request`
- `source_concentration_evidence`
- `distributed_source_evidence`
- `sustained_pressure_evidence`
- `service_stress_evidence`
- `latency_evidence`
- `error_evidence`
- `health_check_failure`
- `nginx_access_evidence`
- `webapp_request_completion`
- `wazuh_confirmation`
- `wazuh_alert_context`
- `irrelevant`

Evidence scores:

- `0` = irrelevant
- `1` = weak supporting evidence
- `2` = useful supporting evidence
- `3` = strong evidence that should appear in the incident graph/report

Every explanation label row should include `label_source`, `label_confidence`, `label_reason`, and `needs_human_review`. Explanation labels are AI-assisted / rule-assisted weak labels, not perfect manually verified human ground truth.

Do not modify existing dataset outputs when building this layer. New files should go under `exports\explanation-labels` and `exports\model-ready-explanation`.

## Daily workflow

```powershell
cd "C:\D\xdr-lab-telemetry"
.\scripts\start-and-check-lab.ps1
```

Quick health check without generating a new login event:

```powershell
.\scripts\start-and-check-lab.ps1 -SkipLinkedEvidenceTest
```

Generate labelled controlled telemetry:

```powershell
.\scripts\generate-controlled-telemetry.ps1 -Scenario Benign -Rounds 1
.\scripts\generate-controlled-telemetry.ps1 -Scenario Benign -Rounds 1 -Randomize -ActorProfile careless_user
.\scripts\generate-controlled-telemetry.ps1 -Scenario UnauthorizedAccess -Rounds 1 -Intensity Low
.\scripts\generate-controlled-telemetry.ps1 -Scenario UnauthorizedAccess -Rounds 2 -Intensity Medium -Randomize -ActorProfile attacker_noisy
.\scripts\generate-controlled-telemetry.ps1 -Scenario SqliProbe -Rounds 1 -Intensity Low
.\scripts\generate-controlled-telemetry.ps1 -Scenario LightDos -Rounds 1 -Intensity Low
.\scripts\generate-controlled-telemetry.ps1 -Scenario AttackerHostLightDos -Rounds 1 -Intensity Low -Randomize
.\scripts\generate-controlled-telemetry.ps1 -Scenario MixedDemo -Rounds 1 -Intensity Low
```

`MultiSourceLightDos` is guarded and refuses to run unless explicit real lab source hosts are provided and at least two visible source IPs can be detected. Do not use it through large batches until a manual smoke test confirms multiple visible source IPs in victim logs.

After caching logs, verify and export a labelled run:

```powershell
.\scripts\cache-lab-logs.ps1
.\scripts\verify-log-output.ps1 -MetadataPath "exports\test-ua-001-metadata.json" -UseLocalLogs
.\scripts\export-lab-logs.ps1 -MetadataPath "exports\test-ua-001-metadata.json" -RunVerification
```

Preview a dataset batch plan without generating telemetry:

```powershell
.\scripts\run-dataset-batch.ps1 -DryRun
```

Example separated validation batch:

```powershell
.\scripts\run-dataset-batch.ps1 `
  -Scenarios Benign,LightDos `
  -RunsPerScenario 1 `
  -Intensities Low `
  -Randomize `
  -InterRunDelaySeconds 30
```

## Dataset-quality telemetry

`scripts/generate-controlled-telemetry.ps1` creates labelled scenario runs for later Wazuh collection, normalization, windowing, and AI model training. Each run writes metadata to `exports/latest-run-metadata.json` by default.

Supported scenarios:

- `Benign` - normal browsing, searches, health checks, successful login, admin access as admin, and moderate human-like high-activity variants.
- `UnauthorizedAccess` - failed login bursts, unknown-user probing, success after failures, and ATO-style admin access.
- `SqliProbe` - safe SQLi-style strings sent only to `/search?q=`.
- `LightDos` - sequential, rate-limited request-volume telemetry using bounded Low/Medium request ranges.
- `AttackerHostLightDos` - Windows-host single-source application-layer DoS/service-stress telemetry with explicit source provenance.
- `MixedDemo` - combined activity for dashboard and correlation demos, not clean supervised training data.

### Service-impact web logging

The web app writes a `request_completed` JSON event after each handled request. These events include:

- `timestamp`, `service`, and `event_type`
- `status_code`, `method`, `path`, and `endpoint`
- `source_ip` and `user_agent`
- `response_time_ms` and `request_duration_ms`
- `health_check_latency_ms` for `/health`
- `query` and `suspicious` when applicable

These fields allow LightDos and future service-stress runs to measure response latency and status-code distribution, not only request volume. Existing semantic events such as `search_query`, `page_view`, and `web_login_attempt` remain unchanged.

### DoS/DDoS-ready taxonomy

- `AttackerHostLightDos` means Windows-host single-source application-layer DoS/service stress. It maps to `main_label=DoS_DDoS`, uses `attack_mode=DoS_HTTP_Flood`, and must have `distributed=false` with one visible source.
- `MultiSourceLightDos` is reserved conceptually for a future multi-source DDoS-like HTTP flood. It must not be used until victim logs show multiple source IPs.

The current Windows-host stage is DoS, not DDoS. The generator dynamically records its best route-selected Windows source IP and verification compares it with Web app and nginx observations.

Safe `LightDos` request ranges:

- Low: 8-15 total sequential requests
- Medium: 16-30 total sequential requests
- High: accepted only as a legacy value and bounded to the Medium range
- Concurrency: 1
- No parallel jobs, runspaces, external targets, packet capture, or destructive outage goal

Safe `AttackerHostLightDos` limits:

- Low: 12-24 total sequential requests
- Medium: 25-40 total sequential requests
- High: accepted only as a legacy value and bounded to the Medium range
- Global hard cap: 40
- Concurrency: 1
- Exactly one generator round per run
- No parallel jobs, runspaces, external targets, packet capture, or destructive outage goal
- Abort after three consecutive request failures

Metadata records scenario variation and request planning fields, including `planned_request_count`, `actual_request_count`, `scenario_variant`, `benign_activity_level`, `generator_version`, `safety_limit_applied`, and `target_endpoint_family`. Attacker-host runs also record attacker host/source provenance, target, traffic tool, attack mode, source/distribution expectations, request/duration caps, concurrency, and target paths.

Benign scenario variants:

- `normal_browsing`
- `search_heavy_benign`
- `healthcheck_heavy_benign`
- `login_admin_workflow`
- `mixed_normal_usage`

When `-Randomize` is used, each Benign run chooses one of these variants. Search-heavy Benign traffic uses human-looking repeated case-review searches, not attack-like query names. Benign queries must not use `burst`, `attacker-host-burst`, `dos`, or `flood`, and Benign generation must stay sequential, delayed, lab-only, and bounded.

Run one bounded Windows-host single-source DoS test:

```powershell
.\scripts\run-dataset-batch.ps1 `
  -Scenarios AttackerHostLightDos `
  -RunsPerScenario 1 `
  -Intensities Low `
  -Randomize `
  -InterRunDelaySeconds 30

.\scripts\export-wazuh-evidence-for-batch.ps1 `
  -BatchManifestPath "exports\batches\<new-batch-id>\batch-manifest.json" `
  -TimePaddingSeconds 10

.\scripts\build-dataset-quality-summary.ps1 `
  -BatchManifestPath "exports\batches\<new-batch-id>\batch-manifest.json"
```

Verification expects one Web app source and one nginx source, same-source ratios of at least `0.95`, burst `request_completed` events, status/duration fields, and sufficient nginx burst entries. A metadata-to-observed source-IP mismatch is reported as WARN for the first implementation.

Test one bounded LightDos run after deploying the web app update:

```powershell
.\scripts\start-and-check-lab.ps1 -SkipLinkedEvidenceTest
.\scripts\run-dataset-batch.ps1 -Scenarios LightDos -RunsPerScenario 1 -Intensities Low -Randomize
.\scripts\export-wazuh-evidence-for-batch.ps1 `
  -BatchManifestPath "exports\batches\<new-batch-id>\batch-manifest.json" `
  -TimePaddingSeconds 10
```

Useful parameters:

```powershell
.\scripts\generate-controlled-telemetry.ps1 `
  -Scenario UnauthorizedAccess `
  -Rounds 3 `
  -Intensity Medium `
  -Randomize `
  -ActorProfile attacker_noisy `
  -RunId "ua-medium-demo-001" `
  -OutputMetadataPath "exports\ua-medium-demo-001-metadata.json"
```

Check logs afterward:

```powershell
multipass exec auth-server -- tail -n 40 /home/ubuntu/auth-lab/logs/auth.log
multipass exec web-server -- tail -n 40 /home/ubuntu/web-lab/logs/webapp.log
multipass exec web-server -- sudo tail -n 40 /var/log/nginx/access.log
```

## Verify telemetry evidence

`scripts/verify-log-output.ps1` reads a telemetry metadata file, filters log lines by the recorded run window, and checks whether the expected evidence exists. It does not generate new telemetry.

Preferred Windows workflow: cache logs with `multipass transfer`, then verify from local files. This avoids calling `multipass exec` from inside the verifier.

```powershell
.\scripts\cache-lab-logs.ps1
.\scripts\verify-log-output.ps1 -MetadataPath "exports\test-dos-001-metadata.json" -UseLocalLogs -ShowMatchedLines
```

Full-copy mode is the default and is best for the current small lab logs. For larger logs later, cache only recent lines:

```powershell
.\scripts\cache-lab-logs.ps1 -TailLines 500
```

Verify the latest run metadata:

```powershell
.\scripts\cache-lab-logs.ps1
.\scripts\verify-log-output.ps1 -UseLocalLogs
```

Verify a specific metadata file:

```powershell
.\scripts\verify-log-output.ps1 -MetadataPath "exports\test-benign-001-metadata.json" -UseLocalLogs
```

Show matched log lines under each check:

```powershell
.\scripts\verify-log-output.ps1 -MetadataPath "exports\test-sqli-001-metadata.json" -UseLocalLogs -ShowMatchedLines
```

Limit remote log reads if needed:

```powershell
.\scripts\verify-log-output.ps1 -MetadataPath "exports\test-dos-001-metadata.json" -TailLines 1000 -ShowMatchedLines
```

Use strict mode for automation. In strict mode, missing required evidence exits with code `1`:

```powershell
.\scripts\verify-log-output.ps1 -MetadataPath "exports\test-ua-001-metadata.json" -UseLocalLogs -Strict
```

Recommended verification commands:

```powershell
.\scripts\cache-lab-logs.ps1
.\scripts\verify-log-output.ps1 -MetadataPath "exports\test-benign-001-metadata.json" -UseLocalLogs -ShowMatchedLines
.\scripts\verify-log-output.ps1 -MetadataPath "exports\test-ua-001-metadata.json" -UseLocalLogs -ShowMatchedLines
.\scripts\verify-log-output.ps1 -MetadataPath "exports\test-sqli-001-metadata.json" -UseLocalLogs -ShowMatchedLines
.\scripts\verify-log-output.ps1 -MetadataPath "exports\test-dos-001-metadata.json" -UseLocalLogs -ShowMatchedLines
.\scripts\verify-log-output.ps1 -MetadataPath "exports\test-mixed-001-metadata.json" -UseLocalLogs -ShowMatchedLines
```

## Export verified run evidence

`scripts/export-lab-logs.ps1` packages one verified scenario run into a clean raw evidence folder for later Wazuh-linked dataset construction, normalization, windowing, and ML preprocessing. It uses only local cached logs under `exports\log-cache`; it does not call Multipass.

Export a run after caching and verification:

```powershell
.\scripts\cache-lab-logs.ps1
.\scripts\export-lab-logs.ps1 -MetadataPath "exports\test-ua-001-metadata.json" -RunVerification
```

The exporter writes to `exports\verified-runs\<run_id>\` by default:

- `metadata.json`
- `manifest.json`
- `README.md`
- `auth-slice.log`
- `webapp-slice.log`
- `nginx-access-slice.log`

If the output folder already exists, rerun with `-Force` only when you intentionally want to replace that package:

```powershell
.\scripts\export-lab-logs.ps1 -MetadataPath "exports\test-ua-001-metadata.json" -RunVerification -Force
```

## Export Wazuh evidence

Before Wazuh-linked dataset generation or Wazuh evidence export, synchronize endpoint agents with the current `wazuh-server` bridged IP. Multipass DHCP can change VM addresses, and endpoint agents keep the manager IP in `/var/ossec/etc/ossec.conf`.

Preview the intended changes:

```powershell
.\scripts\sync-wazuh-agent-manager-ip.ps1 -WhatIf
```

Apply the sync and restart endpoint agents:

```powershell
.\scripts\sync-wazuh-agent-manager-ip.ps1
```

Useful options:

```powershell
.\scripts\sync-wazuh-agent-manager-ip.ps1 `
  -WazuhInstance wazuh-server `
  -AgentInstances auth-server,web-server,db-server

.\scripts\sync-wazuh-agent-manager-ip.ps1 -SkipRestart
```

The script detects the current manager IP, backs up each endpoint's `/var/ossec/etc/ossec.conf`, updates only the manager `<server><address>...</address></server>` value, restarts `wazuh-agent` unless `-SkipRestart` is used, checks recent endpoint `ossec.log` lines, and prints `agent_control -lc` from the manager.

`scripts/export-wazuh-evidence.ps1` slices Wazuh archive and alert JSON events to one run's padded metadata window. It writes Wazuh JSONL slices and a structured evidence summary into the existing verified-run folder, then adds a `wazuh_evidence` section to `manifest.json` when the manifest exists.

```powershell
.\scripts\export-wazuh-evidence.ps1 `
  -MetadataPath "exports\lightdos-20260602T213618Z-004-metadata.json"
```

Export Wazuh evidence for every completed, verification-passed run in a batch:

```powershell
.\scripts\export-wazuh-evidence-for-batch.ps1 `
  -BatchManifestPath "exports\batches\<batch-id>\batch-manifest.json" `
  -TimePaddingSeconds 10
```

Each processed verified-run folder receives:

- `wazuh-archives-slice.json`
- `wazuh-alerts-slice.json`
- `wazuh-evidence-summary.json`

## Build dataset quality summaries

`scripts/build-dataset-quality-summary.ps1` creates a one-row-per-run CSV feature preview from verified local evidence and Wazuh evidence summaries. It also writes a JSON batch summary with scenario/label counts and missing-file warnings.

```powershell
.\scripts\build-dataset-quality-summary.ps1 `
  -BatchManifestPath "exports\batches\training-batch-20260604T182359Z\batch-manifest.json"
```

Default outputs:

- `exports\dataset-quality\<batch_id>-quality-summary.csv`
- `exports\dataset-quality\<batch_id>-quality-summary.json`

The preview includes scenario variation metadata, planned/actual request counts, local slice counts, Wazuh source/decoder counts, Wazuh archive evidence presence, request-completion and search counts, human repeated-search counts, page/admin/login workflow counts, status-code groups, response/request-duration statistics, health-check latency statistics, and invalid Web app JSON line counts. Missing evidence files produce warnings instead of stopping the whole batch summary.

## Build ML feature tables

`scripts/build-ml-feature-table.ps1` creates a model-ready one-row-per-run feature table from a batch manifest and the matching `exports\verified-runs\<run_id>\` folders. It reads existing local evidence only; it does not generate traffic, call Multipass, or modify verified evidence.

```powershell
.\scripts\build-ml-feature-table.ps1 `
  -BatchManifestPath "exports\batches\training-batch-20260605T201054Z\batch-manifest.json"
```

Default outputs:

- `exports\ml-features\<batch_id>-features.csv`
- `exports\ml-features\<batch_id>-features.json`

Rows preserve run labels, scenario variation metadata, planned/actual request counts, clean-training suitability, local evidence counts, Benign workflow/activity counts, Wazuh archive/alert counts, Wazuh archive evidence presence, HTTP status buckets, response-time statistics, source-distribution fields, DoS/DDoS provenance fields, and source evidence paths.

## Build windowed datasets

Window-level rows are used for timeline/stage work. They are read-only over existing verified run folders.

```powershell
.\scripts\build-windowed-dataset.ps1 `
  -BatchManifestPath "exports\batches\<batch-id>\batch-manifest.json" `
  -WindowSeconds 5 `
  -StepSeconds 5 `
  -IncludeWazuh `
  -IncludeRawEvidenceRefs
```

Default outputs:

- `exports\windowed-datasets\<batch_id>-windows.csv`
- `exports\windowed-datasets\<batch_id>-windows.json`
- `exports\windowed-datasets\<batch_id>-window-build-summary.json`

Stage labels are heuristic candidates only. Manual review is required before using stage labels for training.

## Build manual labelling candidates

```powershell
.\scripts\build-labelling-candidates.ps1 `
  -BatchManifestPath "exports\batches\<batch-id>\batch-manifest.json"
```

Default outputs:

- `exports\labelling-candidates\<batch_id>-stage-label-candidates.csv`
- `exports\labelling-candidates\<batch_id>-evidence-label-candidates.csv`
- `exports\labelling-candidates\<batch_id>-labelling-guide.md`

These are review candidates, not the final explanation-label layer. The next explanation-label scripts should create separate outputs under `exports\explanation-labels` and `exports\model-ready-explanation`.

## Build model-ready exports

```powershell
.\scripts\build-model-ready-dataset.ps1 `
  -BatchManifestPath "exports\batches\<batch-id>\batch-manifest.json"
```

Default outputs:

- `exports\model-ready\<batch_id>-model-ready-run-level.csv`
- `exports\model-ready\<batch_id>-model-ready-run-level.json`
- `exports\model-ready\<batch_id>-removed-columns.json`
- `exports\model-ready\<batch_id>-data-dictionary.md`

This export removes scenario names, sublabels, variants, actor profiles, run IDs, file paths, raw text, string IP addresses, and direct attack-mode metadata from model inputs. `main_label` remains as the target.

## Create a v2 dataset plan

Create a plan without running traffic:

```powershell
.\scripts\new-v2-dataset-plan.ps1 -OutputPlanName "dataset-v2-dryrun"
```

The plan writes `exports\plans\<plan_id>\dataset-v2-plan.json`, `dataset-v2-plan.md`, and a staged `run-v2-dataset.ps1`. Review the plan before running any generated stage.

## Run dataset batches

`scripts/run-dataset-batch.ps1` coordinates repeated scenario runs for training-data collection. For each planned run it can generate telemetry, cache logs, verify the metadata window using local cached logs, and export only verified runs into `exports\verified-runs\<run_id>\`.

Preview the default plan first:

```powershell
.\scripts\run-dataset-batch.ps1 -DryRun
```

Run a small batch:

```powershell
.\scripts\run-dataset-batch.ps1 `
  -Scenarios Benign,UnauthorizedAccess,SqliProbe,LightDos `
  -RunsPerScenario 3 `
  -Intensities Low,Medium `
  -Randomize `
  -InterRunDelaySeconds 30
```

`-InterRunDelaySeconds` defaults to `0`, preserving the original behavior. When it is greater than zero, the runner waits after each completed non-final run. This reduces overlap when later Wazuh exports use padded evidence windows. The configured value is written to the batch header, manifest, and generated batch README.

The delay reduces cross-run overlap; it does not remove normal background Wazuh events such as journald, authentication, or system inventory activity. Preserve source paths and provenance during normalization.

When `-ActorProfiles` is omitted, the batch runner chooses scenario-appropriate defaults:

- `Benign`: `normal_user`, `careless_user`, `demo_operator`
- `UnauthorizedAccess`: `attacker_single_ip`, `attacker_noisy`
- `SqliProbe`: `attacker_single_ip`, `attacker_noisy`
- `LightDos`: `attacker_single_ip`, `attacker_noisy`
- `AttackerHostLightDos`: `attacker_single_ip`
- `MixedDemo`: `demo_operator`, `attacker_noisy`

Pass `-ActorProfiles` only when you intentionally want one explicit actor-profile cycle across the whole batch:

```powershell
.\scripts\run-dataset-batch.ps1 `
  -Scenarios Benign,UnauthorizedAccess `
  -RunsPerScenario 2 `
  -ActorProfiles demo_operator,normal_user,attacker_noisy `
  -Randomize
```

The batch runner writes:

- `exports\batches\<batch_id>\batch-manifest.json`
- `exports\batches\<batch_id>\README.md`

Use `-ForceExports` only when intentionally replacing existing verified-run export folders.

Current separated Wazuh-linked reference validation:

- Batch ID: `training-batch-20260604T182359Z`
- Status: `completed`
- Completed: 6
- Failed: 0
- Scenarios: `Benign`, `LightDos`
- Inter-run delay: 30 seconds
- Wazuh evidence padding: 10 seconds
- All runs passed verification, exported successfully, and received Wazuh evidence summaries.

## Safety boundary

All testing must stay inside the user's own isolated academic lab. Do not add destructive exploit code. SQLi-style strings must only be sent to the safe `/search` route. DoS-style request bursts must be optional, light, and rate-limited.

Do not add packet capture unless explicitly requested. Do not directly merge public packet/flow datasets into this Wazuh lab dataset without a separate external-normalized layer. Do not overclaim `AttackerHostLightDos` as true DDoS unless multiple visible source IPs exist in victim logs.

## Documentation map

- `AGENTS.md` - Codex operating instructions.
- `docs/00_PROJECT_CONTEXT_SUMMARY.md` - concise project context.
- `docs/01_lab_build_memory_updated.md` - practical lab build memory.
- `docs/02_official_project_proposal.md` - converted official proposal.
- `docs/03_official_system_build_plan.md` - converted build plan.
- `docs/04_official_ai_development_pipeline.md` - converted AI pipeline.
- `docs/05_incident_taxonomy.md` - converted incident taxonomy table.
- `docs/06_recommended_workflow.md` - source workflow.
- `docs/10_CODEX_NEXT_TASKS.md` - immediate Codex task plan.
- `docs/11_CONTROLLED_TELEMETRY_RUNBOOK.md` - controlled scenario runbook.
- `docs/12_DATASET_V2_IMPROVEMENT_PLAN.md` - historical dataset v2 improvement plan; superseded as the immediate next task by explanation-layer work in `docs/10_CODEX_NEXT_TASKS.md`.
- `docs/12_latest_health_check_and_codex_state.md` - latest confirmed operational and pipeline state.
- `docs/14_HOW_TO_USE_THIS_CONTEXT_PACK_WITH_CODEX.md` - current context-loading workflow.
- `docs/CODEX_CURRENT_STATUS_HANDOFF.md` - current scope, release status, limits, and next prompt summary.
- `docs/CODEX_WEBAPP_LOGGING_PATCH.md` - exact web app logging patch instructions because web app source is not stored locally.
