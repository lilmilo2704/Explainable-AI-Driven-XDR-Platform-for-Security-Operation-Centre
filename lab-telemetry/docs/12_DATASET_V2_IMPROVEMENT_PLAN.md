# Dataset v2 Improvement Plan

Last updated: 2026-06-07

## Current superseding note

As of 2026-06-09, the official clean dataset release has been built from `training-batch-20260607T132426Z`. The immediate next engineering direction is no longer the v2 generation plan below. Future Codex sessions should treat this file as historical planning context and use `docs/10_CODEX_NEXT_TASKS.md` for the current task order.

Current official dataset facts:

- 300 tabular runs.
- 100 `Benign` runs.
- 100 `LightDos` runs.
- 100 `AttackerHostLightDos` runs.
- 200 `DoS_DDoS`-labelled runs total.
- 798 windowed rows.
- 300 model-ready run-level rows.
- 299 raw verified-run evidence folders.
- `benign-20260607T132426Z-043` is the known incomplete run and is intentionally missing from raw evidence.

Current immediate direction: build the explanation-labelling layer under `exports\explanation-labels` and `exports\model-ready-explanation` without modifying existing dataset outputs.

This plan records the next dataset-improvement tasks. It is a planning document only; do not run large batches automatically.

## Priority 1 - Add Harder Benign Variants

Goal: make benign traffic less trivially separable from DoS/service-stress by adding legitimate repeated searches, health checks, dashboard-style refreshes, login/admin workflows, and mixed normal usage that can overlap with DoS request counts without using attack-like query strings.

Affected scripts:

- `scripts/generate-controlled-telemetry.ps1`
- `scripts/verify-log-output.ps1`
- `scripts/build-dataset-quality-summary.ps1`
- `scripts/build-ml-feature-table.ps1`

Expected output:

- New benign metadata variants.
- Verified benign evidence with normal query strings.
- Feature fields that distinguish normal repetition from attack-like bursts.

Safety notes:

- Keep traffic sequential, delayed, and lab-only.
- Do not use `burst`, `attacker-host-burst`, `dos`, or `flood` in benign query strings.
- Do not create failed-login bursts as benign activity.

Validation command:

```powershell
.\scripts\run-dataset-batch.ps1 -Scenarios Benign -RunsPerScenario 1 -Intensities Low -Randomize -DryRun
```

## Priority 2 - Add More Varied DoS Variants

Goal: reduce deterministic DoS patterns by varying endpoint mix, request pacing, query names, user agents where appropriate, and low/medium intensity behavior while keeping all runs bounded and explainable.

Affected scripts:

- `scripts/generate-controlled-telemetry.ps1`
- `scripts/verify-log-output.ps1`
- `scripts/build-dataset-quality-summary.ps1`
- `scripts/build-ml-feature-table.ps1`

Expected output:

- More diverse `LightDos` and `AttackerHostLightDos` metadata variants.
- Less dependence on a single query substring.
- Feature tables that preserve `attack_mode`, source provenance, and endpoint-family metadata.

Safety notes:

- Stay within existing request caps.
- Keep concurrency at 1 unless a later prompt explicitly changes safety rules.
- Do not target external systems.
- Do not call single-source runs DDoS.

Validation command:

```powershell
.\scripts\run-dataset-batch.ps1 -Scenarios LightDos,AttackerHostLightDos -RunsPerScenario 1 -Intensities Low -Randomize -DryRun
```

## Priority 3 - Strengthen Service-Impact and Degradation Features

Goal: improve evidence for service impact by using existing `request_completed` fields and adding feature extraction around status buckets, latency, request duration, health-check latency, failure counts, and route-specific degradation patterns.

Affected scripts:

- `scripts/verify-log-output.ps1`
- `scripts/build-dataset-quality-summary.ps1`
- `scripts/build-ml-feature-table.ps1`
- Optional future app logging changes only if explicitly requested.

Expected output:

- Better per-run service-impact metrics.
- Clear distinction between request volume and actual service degradation.
- Warnings when a run has insufficient degradation evidence.

Safety notes:

- Do not attempt destructive outage generation.
- Most current runs have no 4xx/5xx/error events; document that honestly.
- Treat latency as contextual evidence, not the only classifier signal.

Validation command:

```powershell
.\scripts\build-dataset-quality-summary.ps1 -BatchManifestPath "exports\batches\training-batch-20260607T132426Z\batch-manifest.json"
```

## Priority 4 - Build a Clean Model-Ready Dataset Export

Goal: create a compact baseline export that removes label leakage, provenance-only fields, file paths, and raw evidence text while preserving the target label and safe numeric/categorical features.

Affected scripts:

- `scripts/build-ml-feature-table.ps1`
- New helper script if clearer, for example `scripts/build-clean-ml-dataset.ps1`.

Expected output:

- `exports/ml-features/<batch_id>-clean-features.csv`
- `exports/ml-features/<batch_id>-clean-features.json`
- A column manifest listing included features, excluded leakage columns, and target column.

Safety notes:

- Do not train models in this repository.
- Do not include `scenario`, `sublabel`, `scenario_variant`, `actor_profile`, `attack_mode`, source IPs, paths, run IDs, or raw log text as baseline model features.
- Keep raw-content exports for traceability only.

Validation command:

```powershell
.\scripts\build-ml-feature-table.ps1 -BatchManifestPath "exports\batches\training-batch-20260607T132426Z\batch-manifest.json"
```

## Priority 5 - Build a Window-Level Dataset Builder

Goal: move beyond run-level rows by building time-window feature rows from verified local and Wazuh evidence while preserving run IDs, labels, source paths, window boundaries, and Wazuh provenance.

Affected scripts:

- New script, for example `scripts/build-windowed-feature-table.ps1`.
- `scripts/build-ml-feature-table.ps1` as a reference, not necessarily as the implementation target.

Expected output:

- `exports/ml-features/<batch_id>-windowed-features.csv`
- `exports/ml-features/<batch_id>-windowed-features.json`
- Window manifest with `run_id`, `window_start_utc`, `window_end_utc`, source paths, and event counts.

Safety notes:

- Read existing verified evidence only.
- Do not generate traffic.
- Do not create labels from Wazuh alerts.
- Keep run/window provenance separate from model input features.

Validation command:

```powershell
Test-Path "exports\batches\training-batch-20260607T132426Z\batch-manifest.json"
```

## Priority 6 - Build Manual Labelling Candidate Generator

Goal: create candidate files for manual stage labels and evidence labels so a human can review important windows/events before stage/storyline modelling.

Affected scripts:

- New script, for example `scripts/build-labelling-candidates.ps1`.
- May reuse parsers from quality/feature scripts.

Expected output:

- `exports/labelling-candidates/<batch_id>-stage-candidates.csv`
- `exports/labelling-candidates/<batch_id>-evidence-candidates.csv`
- Candidate rows with run ID, timestamps, source, event summary, suggested reason, and review columns.

Safety notes:

- Candidate labels are suggestions, not ground truth.
- Do not auto-label stages from Wazuh alerts alone.
- Preserve raw evidence references for review without using raw text as baseline classifier input.

Validation command:

```powershell
Test-Path "exports\verified-runs"
```

## Priority 7 - Add Safe MultiSourceLightDos Support Only If Real Source Diversity Exists

Goal: add a future DDoS-like scenario only when the victim logs can show multiple visible source IPs from real lab sources.

Affected scripts:

- `scripts/generate-controlled-telemetry.ps1`
- `scripts/run-dataset-batch.ps1`
- `scripts/verify-log-output.ps1`
- `scripts/export-lab-logs.ps1`
- `scripts/build-dataset-quality-summary.ps1`
- `scripts/build-ml-feature-table.ps1`

Expected output:

- A `MultiSourceLightDos` scenario only if source diversity is real.
- Metadata showing `distributed=true`, `source_count > 1`, and observed source counts.
- Victim logs showing multiple visible source IPs.

Safety notes:

- Do not fake source IPs.
- Do not claim DDoS without multiple visible source IPs in victim logs.
- Do not add packet capture.
- Keep request rates bounded and lab-only.

Validation command:

```powershell
.\scripts\run-dataset-batch.ps1 -Scenarios AttackerHostLightDos -RunsPerScenario 1 -Intensities Low -Randomize -DryRun
```

## Priority 8 - Create a v2 Dataset Generation Plan

Goal: define a balanced v2 batch plan after implementation changes are smoke-tested, including counts, intensities, scenario mix, expected outputs, and handoff artifacts.

Affected scripts:

- `scripts/run-dataset-batch.ps1`
- `scripts/export-wazuh-evidence-for-batch.ps1`
- `scripts/build-dataset-quality-summary.ps1`
- `scripts/build-ml-feature-table.ps1`
- Future clean/window/labelling scripts.

Expected output:

- A written v2 batch plan in `docs/`.
- Dry-run manifest for planned v2 generation.
- No automatic huge batch execution.

Safety notes:

- Use dry-run planning first.
- Keep inter-run delay to reduce Wazuh window overlap.
- Run only after the user explicitly approves data generation.

Validation command:

```powershell
.\scripts\run-dataset-batch.ps1 -Scenarios Benign,LightDos,AttackerHostLightDos -RunsPerScenario 1 -Intensities Low -Randomize -InterRunDelaySeconds 45 -DryRun
```

## Priority 9 - Generate New v2 Dataset Only After Smoke Testing

Goal: create a new v2 dataset only after the implementation changes pass one-run smoke tests and the user approves generation.

Affected scripts:

- `scripts/start-and-check-lab.ps1`
- `scripts/run-dataset-batch.ps1`
- `scripts/export-wazuh-evidence-for-batch.ps1`
- `scripts/build-dataset-quality-summary.ps1`
- `scripts/build-ml-feature-table.ps1`
- Future clean/window/labelling scripts.

Expected output:

- New v2 batch manifest.
- Verified run folders.
- Wazuh evidence slices/summaries.
- Quality summary.
- ML feature tables.
- Clean model-ready export.
- Window-level export.
- Labelling candidate files.

Safety notes:

- Do not run huge batches automatically.
- Start with one-run smoke tests.
- Confirm Wazuh agents are active before approved generation.
- Keep DDoS wording honest.

Validation command:

```powershell
.\scripts\start-and-check-lab.ps1 -SkipLinkedEvidenceTest
```

## Do Not Do Yet

- Do not train models.
- Do not add packet capture.
- Do not target external systems.
- Do not fake source IPs.
- Do not rely on Wazuh alerts as ground truth labels.
- Do not run large batches without explicit user approval.
