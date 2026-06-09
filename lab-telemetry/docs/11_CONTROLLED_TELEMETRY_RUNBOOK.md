# Controlled Telemetry Runbook

## Purpose

This runbook defines how to safely generate benign and attack-like telemetry inside the user's own isolated Coding Fest 2026 XDR/SOC lab.

The goal is to produce structured logs for Wazuh collection, normalization, incident correlation, dataset construction, and AI/XAI work. The goal is not to damage services or perform real exploitation.

## Current dataset status

The current project focus is a log-centric, Wazuh-linked XDR dataset and prototype pipeline for detecting and explaining application-layer DoS/DDoS/service-stress incidents. The current focus is not broad multi-incident detection.

The official dataset batch is `training-batch-20260607T132426Z`.

Official clean release package:

```text
exports\dataset-releases\coding-fest-2026-xdr-dataset-training-batch-20260607T132426Z-clean\
exports\dataset-releases\coding-fest-2026-xdr-dataset-training-batch-20260607T132426Z-clean.zip
```

Known dataset facts:

- 300 tabular runs.
- 100 `Benign` runs.
- 100 `LightDos` runs.
- 100 `AttackerHostLightDos` runs.
- 200 `DoS_DDoS`-labelled runs total.
- 798 windowed rows.
- 300 model-ready run-level rows.
- 299 raw verified-run evidence folders.
- `benign-20260607T132426Z-043` is the known incomplete run.
- `benign-20260607T132426Z-043` failed verification/export and is intentionally missing from raw evidence.
- For clean supervised training, use `is_clean_supervised_training_candidate == True`.

The current ML label target is `Benign` vs `DoS_DDoS`. `LightDos` and `AttackerHostLightDos` map to `DoS_DDoS`, but the underlying data is mostly controlled application-layer single-source DoS/service-stress. Do not claim it is complete real DDoS data until multiple visible source IPs appear in victim logs.

Current generated artifacts include verified run folders, Wazuh archive/alert slices, Wazuh evidence summaries, dataset quality summaries, ML feature tables, raw-content ML feature exports, windowed datasets, model-ready datasets, and clean dataset release folders.

Next planned work is the explanation-labelling layer: stage labels, evidence roles, evidence scores, model-ready explanation datasets, quality reports, and an explanation-enriched release.

## Why labelled scenario runs matter

The lab should produce dataset-quality controlled telemetry, not just a large number of logs. Each run should have a clear label, sublabel, actor profile, intensity, timestamp window, and metadata file. This supports later:

- Wazuh-linked event export
- normalization into structured records
- incident windowing
- supervised labels for AI experiments
- explainability and causal timeline work

Diverse but bounded telemetry is better than identical repeated scripts. Repeating the exact same sequence can overfit later models to script artifacts. Safe variation in search terms, failed-login counts, username order, and timing makes the dataset more realistic while preserving control and explainability.

The metadata fields are important:

- `run_id` links logs, Wazuh alerts, exported records, and training rows.
- `main_label` maps to the official incident class.
- `sublabel` captures the specific scenario pattern, such as `ato_progression` or `union_select_probe`.
- `actor_profile` records the intended behavior style.
- `intensity` records safe volume settings used for feature interpretation.
- `planned_request_count` and `actual_request_count` record intended and attempted HTTP request volume for the run.
- `scenario_variant` records the selected behavior variant.
- `benign_activity_level` records baseline, moderate search, moderate health-check, admin workflow, or mixed normal usage activity when applicable.
- `generator_version` records the telemetry generator behavior version.
- `safety_limit_applied` records when a legacy or requested setting was bounded for safety.
- `target_endpoint_family` records the route family exercised by the scenario.
- `expected_ml_features` describes the feature families expected from the run.

`MixedDemo` is useful for dashboard demos and correlation testing. It is not ideal for clean supervised model training because multiple scenario classes are intentionally mixed inside one run.

## Safety boundary

- Only target the lab IPs.
- Do not run destructive exploit code.
- SQLi-style activity is only a string input to `/search`; it is safely detected and logged by the app.
- DoS-style activity is optional, light, and rate-limited.
- The script should be explainable in an academic report.

## Lab endpoints

- Auth API: `http://<auth-server-ip>:8000`
- Web app through nginx: `http://<web-server-ip>`

The batch and health-check automation resolves current bridged DHCP addresses. Use `multipass list` when running commands manually.

## Generator script

Use:

```powershell
.\scripts\generate-controlled-telemetry.ps1 -Scenario Benign -Rounds 1
```

Common parameters:

- `-Scenario`: `Benign`, `UnauthorizedAccess`, `SqliProbe`, `LightDos`, `AttackerHostLightDos`, or `MixedDemo`
- `-Rounds`: number of labelled scenario rounds
- `-DelayMs`: delay between requests
- `-RunId`: optional run identifier
- `-Randomize`: safe variation in order, timing, and payload selection
- `-Intensity`: `Low`, `Medium`, or `High`
- `-ActorProfile`: `normal_user`, `careless_user`, `attacker_single_ip`, `attacker_noisy`, or `demo_operator`
- `-OutputMetadataPath`: metadata destination, default `exports/latest-run-metadata.json`

## Scenario A - Benign activity

Purpose: generate normal baseline logs.

Supported variants:

- `normal_browsing`: ordinary page views, a few searches, successful login, and admin access.
- `heavy_search_benign`: moderate to high normal searches with non-attack query terms.
- `healthcheck_heavy_benign`: repeated but moderate health checks interleaved with normal browsing.
- `repeated_endpoint_benign`: repeated normal page, login, and search requests.
- `mixed_user_journey_benign`: bounded health, page, search, login, and admin workflow.
- `benign_burst_without_attack`: short high-activity benign sequence with normal search terms.

When `-Randomize` is used, Benign randomly chooses one of these variants. Without `-Randomize`, Benign uses `normal_browsing`.

Benign query safety:

- Do not use attack-like query names such as `burst`, `attacker-host-burst`, `dos`, or `flood`.
- Do not send SQLi payloads.
- Do not create failed-login bursts.
- Do not use tight request loops or source-distribution manipulation.
- Keep all traffic sequential, delayed, lab-only, and bounded.

Typical steps:

1. GET `/health`
2. GET `/`
3. GET `/login`
4. GET `/search?q=security`
5. GET `/search?q=dashboard`
6. POST `/login` with valid `admin` credentials
7. GET `/admin?user=admin`

Expected web events:

- `page_view`
- `search_query`
- `web_login_attempt` with `login_success`
- `admin_route_access`

Expected auth events:

- `login_success`

Expected features:

- low failed-login count
- normal search-query count
- possible human repeated-search count for search-heavy variants
- successful-login count
- no suspicious-query count

## Scenario B - Unauthorized Access / ATO-style telemetry

Purpose: generate identity abuse evidence.

Steps:

1. Open login page.
2. Attempt several failed logins for `admin`.
3. Perform one successful login for `admin`.
4. Access `/admin?user=admin`.

Expected event sequence:

```text
login_failed
login_failed
login_failed
login_success
admin_route_access
```

Correlation fields:

- timestamp
- username
- source IP
- user-agent
- result/reason

Expected incident interpretation:

- suspicious failed-burst to success transition
- possible credential stuffing / ATO-style behavior

Supported sublabels:

- `brute_force_failed_only`
- `credential_stuffing`
- `success_after_failures`
- `ato_progression`

Expected features:

- failed-login count and rate
- unknown-user count
- unique-username count
- success-after-failures
- admin-access-after-success
- same-source repeated attempts

## Scenario C - Unknown-user probing

Purpose: generate reconnaissance or credential probing evidence.

Attempt login with usernames such as:

- `root`
- `administrator`
- `backup`
- `postgres`

Expected auth events:

- `login_failed`
- reason: `unknown_user`

Expected web events:

- `web_login_attempt`
- reason: `login_failed`

## Scenario D - SQLi-style suspicious web telemetry

Purpose: generate Data Breach / web exploitation preparation evidence.

Send safe suspicious strings to `/search`, such as:

- `' OR '1'='1`
- `UNION SELECT username,password FROM users`
- `information_schema.tables`
- `admin'--`
- `; DROP TABLE users;`

Expected web events:

- `suspicious_query`
- `suspicious=true`
- reason starts with `matched_pattern:`

Important: this does not exploit the database. It only triggers the safe detection logic already present in the web app.

Supported sublabels:

- `basic_sqli_probe`
- `union_select_probe`
- `information_schema_probe`
- `comment_bypass_probe`
- `mixed_sqli_probe`

Expected features:

- suspicious-query count
- SQLi-pattern count
- union-select count
- information-schema count
- comment-marker count
- normal-search-before-after context

## Scenario E - Light DoS-style request-volume telemetry

Purpose: generate request-volume evidence for later DoS analytics.

Use only with the `LightDos` scenario.

Rules:

- Low range: 10-20 total sequential requests.
- Medium range: 21-35 total sequential requests.
- High range: 36-50 total sequential requests.
- Include short sleeps between requests.
- Target normal app routes such as `/`, `/health`, `/login`, and `/search?q=<normal-term>`.

DoS variants:

- `search_endpoint_pressure`
- `health_endpoint_pressure`
- `homepage_refresh_pressure`
- `mixed_endpoint_pressure`
- `login_page_pressure`
- `slow_low_rate_pressure`
- `short_spike_pressure`
- `sustained_low_pressure`

Expected evidence:

- nginx access log request spike
- repeated web `search_query` events

Expected features:

- request count
- request rate
- repeated-path count
- same-source request ratio
- status-code distribution
- response time in milliseconds
- request duration in milliseconds
- health-check latency in milliseconds
- no destructive service outage required

The web app writes a `request_completed` JSON event for each handled route. It carries `status_code`, `method`, `path`, `endpoint`, `source_ip`, `user_agent`, `response_time_ms`, `request_duration_ms`, and `/health` latency evidence. These fields help distinguish a request burst from measurable service stress or degradation. Existing route-specific events remain available for semantic context.

For new LightDos runs, `verify-log-output.ps1` reports PASS when the new status, duration, path, and method fields are present in the webapp log window. It reports WARN rather than FAIL when older runs lack these fields.

Test the logging improvement with one bounded run:

```powershell
.\scripts\start-and-check-lab.ps1 -SkipLinkedEvidenceTest
.\scripts\run-dataset-batch.ps1 -Scenarios LightDos -RunsPerScenario 1 -Intensities Low -Randomize
.\scripts\export-wazuh-evidence-for-batch.ps1 `
  -BatchManifestPath "exports\batches\<new-batch-id>\batch-manifest.json" `
  -TimePaddingSeconds 10
```

## Scenario E2 - AttackerHostLightDos single-source DoS telemetry

Purpose: generate explicit Windows-host single-source application-layer DoS/service-stress evidence.

Taxonomy:

```text
scenario: AttackerHostLightDos
main_label: DoS_DDoS
sublabel: windows_host_single_source_http_flood
attack_mode: DoS_HTTP_Flood
distributed: false
source_count: 1
```

This scenario is not DDoS because the victim currently sees one attacker/source IP. `MultiSourceLightDos` is reserved for a future DDoS-like scenario and must only be used when victim logs show multiple visible source IPs.

Safe limits:

- Low: 20 sequential requests
- Medium: 21-35 sequential requests
- High: 36-50 sequential requests
- Global hard cap: 50
- Concurrency: 1
- Exactly one generator round per run
- Duration caps: 15/25 seconds for Low/Medium; legacy High uses the Medium cap
- Abort after three consecutive request failures
- No parallel jobs, runspaces, external targets, packet capture, or destructive outage goal

Traffic sequence:

1. Pre-run Auth/Web health checks must pass.
2. Request `/health`.
3. Request `/`.
4. Send sequential requests across `/`, `/health`, `/login`, and `/search?q=<normal-term>`.
5. Request `/login` occasionally during longer bursts.

Metadata includes:

- `attacker_host_type`
- `attacker_source_ip`
- `target_web_base`
- `traffic_tool`
- `attack_mode`
- `distributed`
- `source_count`
- `expected_source_count`
- `expected_distributed`
- `planned_request_count`
- `actual_request_count`
- `scenario_variant`
- `benign_activity_level`
- `generator_version`
- `safety_limit_applied`
- `target_endpoint_family`
- `request_cap`
- `concurrency`
- `duration_cap_seconds`
- `target_paths`
- `source_ip_detection_method`

Verification requires:

- one observed Web app source and one observed nginx source
- same-source ratios of at least `0.95`
- service-pressure `request_completed` evidence
- `status_code` and response/request-duration fields
- sufficient nginx service-pressure entries
- `distributed=false`, `source_count=1`, and `attack_mode=DoS_HTTP_Flood`

If the dynamically detected metadata source IP differs from the observed dominant source IP, verification reports WARN with all values rather than failing the first implementation.

Run one bounded test:

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

## Scenario E3 - MultiSourceLightDos guarded DDoS-like candidate

`MultiSourceLightDos` exists as a guarded scenario. It refuses to run unless explicit source hosts are supplied and at least two visible source IPs can be detected before generation.

Allowed source host names:

- `windows`
- `auth-server`
- `web-server`
- `db-server`

Example manual smoke command:

```powershell
.\scripts\generate-controlled-telemetry.ps1 `
  -Scenario MultiSourceLightDos `
  -RunId "multisource-smoke-001" `
  -SourceHosts windows,auth-server `
  -RequireMultipleSources `
  -MinVisibleSources 2 `
  -Intensity Low `
  -Randomize
```

This is still only a DDoS-like candidate until `verify-log-output.ps1` confirms multiple visible source IPs in webapp/nginx victim logs. Do not fake source IPs and do not claim DDoS from single-source evidence.

## Scenario F - MixedDemo

Purpose: generate a small combined run for dashboard and correlation testing.

Includes:

- benign activity
- UnauthorizedAccess activity
- SqliProbe activity
- LightDos activity

Warning: `MixedDemo` is not ideal for clean supervised model training labels because several incident classes are mixed into one run window.

## Recommended early dataset plan

Start with a small, balanced labelled collection:

- 20 `Benign` runs
- 20 `UnauthorizedAccess` runs
- 15 `SqliProbe` runs
- 10 `LightDos` runs
- `MixedDemo` only for dashboard testing and correlation demos

Recommended collection approach:

```powershell
.\scripts\start-and-check-lab.ps1 -SkipLinkedEvidenceTest
.\scripts\generate-controlled-telemetry.ps1 -Scenario Benign -Rounds 1 -RunId "benign-001"
.\scripts\generate-controlled-telemetry.ps1 -Scenario UnauthorizedAccess -Rounds 1 -Intensity Low -RunId "ua-001"
.\scripts\generate-controlled-telemetry.ps1 -Scenario SqliProbe -Rounds 1 -Intensity Low -RunId "sqli-001"
.\scripts\generate-controlled-telemetry.ps1 -Scenario LightDos -Rounds 1 -Intensity Low -RunId "dos-001"
```

## Verification before export

Verification matters before exporting data because the metadata label is only useful if the expected evidence actually appears in the lab logs. A run should not become training data just because the generator completed; it should first pass scenario-specific checks against Auth, Web, and nginx logs.

`scripts/verify-log-output.ps1` is the read-only verification layer. It:

- reads a metadata JSON file from `exports/`
- uses `run_id`, `scenario`, `sublabel`, `intensity`, `start_time_utc`, and `end_time_utc`
- reads cached local log files, or can pull existing logs with `multipass exec` in remote mode
- filters log lines to the metadata time window with padding
- checks expected evidence for the scenario
- prints a PASS/WARN/FAIL table

On Windows, the preferred method is to cache logs first with `multipass transfer` and then verify from local files. Calling `multipass exec` from inside larger PowerShell scripts while piping or redirecting log output can hang or behave differently from running the same command manually. The transfer-based cache step keeps Multipass interaction simple: it prepares a temporary file inside the VM, transfers that file to `exports\log-cache`, and then the verifier works only with local text files.

Full-copy cache mode is preferred for the current lab because the logs are still small and full files preserve the widest time window for verification. Later, when logs become large, use `-TailLines` to create tailed temporary files inside the VMs before transfer.

Preferred verification workflow:

```powershell
.\scripts\cache-lab-logs.ps1
.\scripts\verify-log-output.ps1 -MetadataPath "exports\test-dos-001-metadata.json" -UseLocalLogs -ShowMatchedLines
.\scripts\verify-log-output.ps1 -MetadataPath "exports\test-sqli-001-metadata.json" -UseLocalLogs -ShowMatchedLines
```

Optional tailed cache for larger logs:

```powershell
.\scripts\cache-lab-logs.ps1 -TailLines 500
```

Default local cache files:

- `exports\log-cache\auth.log`
- `exports\log-cache\webapp.log`
- `exports\log-cache\nginx-access.log`

Verification protects dataset quality by catching:

- empty or missing log windows
- failed metadata-to-log timestamp alignment
- missing Auth evidence for login scenarios
- missing Web evidence for search/admin/login workflows
- missing nginx access evidence for request-volume features
- mixed-label runs that should not be used as clean supervised training data

Interpretation:

- `PASS`: expected evidence was found.
- `WARN`: evidence may still be usable, but review is needed. Examples include `MixedDemo` training warnings or skipped conditional checks.
- `FAIL`: required evidence is missing. Do not export that run as clean training data until the cause is understood.

`MixedDemo` warnings are expected. They remind the analyst that the run intentionally combines multiple behavior classes and is intended for dashboards, Wazuh collection tests, and correlation demos rather than clean single-label supervised training.

Recommended workflow:

1. Start/check the lab:

```powershell
.\scripts\start-and-check-lab.ps1 -SkipLinkedEvidenceTest
```

2. Generate one labelled run:

```powershell
.\scripts\generate-controlled-telemetry.ps1 -Scenario Benign -Rounds 1 -RunId "benign-001" -OutputMetadataPath "exports\benign-001-metadata.json"
```

3. Verify the run:

```powershell
.\scripts\cache-lab-logs.ps1
.\scripts\verify-log-output.ps1 -MetadataPath "exports\benign-001-metadata.json" -UseLocalLogs -ShowMatchedLines
```

4. Later, export the verified run evidence:

```powershell
.\scripts\export-lab-logs.ps1 -MetadataPath "exports\benign-001-metadata.json" -RunVerification
```

Use strict mode when scripting dataset collection:

```powershell
.\scripts\cache-lab-logs.ps1
.\scripts\verify-log-output.ps1 -MetadataPath "exports\benign-001-metadata.json" -UseLocalLogs -Strict
```

## Export verified raw evidence packages

`scripts/export-lab-logs.ps1` turns one verified metadata run into a raw evidence package under:

```text
exports\verified-runs\<run_id>\
```

The exporter uses local cached logs only:

- `exports\log-cache\auth.log`
- `exports\log-cache\webapp.log`
- `exports\log-cache\nginx-access.log`

It does not contact Multipass. Cache logs first, then export:

```powershell
.\scripts\cache-lab-logs.ps1
.\scripts\export-lab-logs.ps1 -MetadataPath "exports\test-ua-001-metadata.json" -RunVerification
```

When `-RunVerification` is used, the exporter runs the local-log verifier first and stops if verification does not pass. This protects the dataset pipeline from exporting a labelled run whose expected evidence is missing.

Each export package contains:

- `metadata.json` - original scenario metadata.
- `manifest.json` - run label, time window, source paths, output paths, line counts, expected evidence fields, training suitability, export time, and verification status.
- `README.md` - short explanation of the exported run and how to use it.
- `auth-slice.log` - Auth JSON log lines in the metadata time window plus padding.
- `webapp-slice.log` - Web app JSON log lines in the metadata time window plus padding.
- `nginx-access-slice.log` - nginx access lines in the metadata time window plus padding.

Use `-Force` only when intentionally replacing an existing export folder:

```powershell
.\scripts\export-lab-logs.ps1 -MetadataPath "exports\test-ua-001-metadata.json" -RunVerification -Force
```

These packages are the preferred raw evidence units for later Wazuh-linked dataset construction, normalization, time-window feature extraction, and ML preprocessing.

## Batch dataset workflow

Before collecting Wazuh-linked dataset batches or exporting Wazuh evidence, synchronize endpoint agents with the current `wazuh-server` Multipass IP. Bridged DHCP addresses can change, and agents store the manager address in `/var/ossec/etc/ossec.conf`.

Preview:

```powershell
.\scripts\sync-wazuh-agent-manager-ip.ps1 -WhatIf
```

Apply:

```powershell
.\scripts\sync-wazuh-agent-manager-ip.ps1
```

The script backs up each endpoint config, updates only the Wazuh manager `<server><address>...</address></server>` value, restarts `wazuh-agent` unless `-SkipRestart` is used, checks recent endpoint `ossec.log`, and prints active agents from `wazuh-server` with `agent_control -lc`.

`scripts/run-dataset-batch.ps1` is the dataset-factory coordination layer. It plans multiple labelled scenario runs, optionally checks lab health, generates one metadata file per run, caches logs, verifies each run using local cached logs, and exports only verified runs.

Preview a batch without generating telemetry:

```powershell
.\scripts\run-dataset-batch.ps1 -DryRun
```

Default dry-run planning uses:

- Scenarios: `Benign`, `UnauthorizedAccess`, `SqliProbe`, `LightDos`
- Runs per scenario: `3`
- Intensities: `Low`, `Medium`
- Actor profiles: scenario-specific defaults when `-ActorProfiles` is omitted

Run a batch when the lab is ready:

```powershell
.\scripts\run-dataset-batch.ps1 `
  -Scenarios Benign,UnauthorizedAccess,SqliProbe,LightDos `
  -RunsPerScenario 3 `
  -Intensities Low,Medium `
  -Randomize `
  -InterRunDelaySeconds 30
```

Use `-InterRunDelaySeconds` when collecting consecutive runs that will later receive padded Wazuh evidence windows. It defaults to `0`. A positive value waits after each completed non-final run, reducing cross-run evidence overlap without changing telemetry generation.

When `-ActorProfiles` is omitted, the batch runner chooses actor profiles that match each scenario:

- `Benign`: `normal_user`, `careless_user`, `demo_operator`
- `UnauthorizedAccess`: `attacker_single_ip`, `attacker_noisy`
- `SqliProbe`: `attacker_single_ip`, `attacker_noisy`
- `LightDos`: `attacker_single_ip`, `attacker_noisy`
- `AttackerHostLightDos`: `attacker_single_ip`
- `MixedDemo`: `demo_operator`, `attacker_noisy`

Scenario-default actor profile mode is working and has been manually validated.

If `-ActorProfiles` is provided explicitly, the batch runner uses the user-provided profiles as a single cycle across the whole batch, preserving the previous manual behavior:

```powershell
.\scripts\run-dataset-batch.ps1 `
  -Scenarios Benign,UnauthorizedAccess `
  -RunsPerScenario 2 `
  -ActorProfiles demo_operator,normal_user,attacker_noisy `
  -Randomize
```

For each planned run, the batch runner performs:

1. `start-and-check-lab.ps1 -SkipLinkedEvidenceTest`, unless `-SkipHealthCheck` is used.
2. `generate-controlled-telemetry.ps1` with `-Rounds 1`, run-specific metadata path, scenario, intensity, actor profile, and optional `-Randomize`.
3. `cache-lab-logs.ps1`.
4. `verify-log-output.ps1 -UseLocalLogs`.
5. `export-lab-logs.ps1 -RunVerification` only if verification passed.

If verification fails, the run is marked failed in the batch manifest and is not exported. The batch continues with the next planned run.

After the local verified-run batch completes, export Wazuh evidence separately:

```powershell
.\scripts\export-wazuh-evidence-for-batch.ps1 `
  -BatchManifestPath "exports\batches\<batch-id>\batch-manifest.json" `
  -TimePaddingSeconds 10
```

The Wazuh exporter copies remote archive/alert files into a readable temporary directory on `wazuh-server`, transfers them into a local cache, then filters local copies. It does not stream large remote files through `multipass exec`.

Batch outputs:

- `exports\batches\<batch_id>\batch-manifest.json`
- `exports\batches\<batch_id>\README.md`
- Per-run metadata under `exports\`
- Verified raw evidence packages under `exports\verified-runs\<run_id>\`

Use `-ForceExports` only when intentionally replacing existing verified-run export folders.

## Current reference validation run

Latest confirmed separated Wazuh-linked validation batch:

```text
Batch ID: training-batch-20260604T182359Z
Status: completed
Completed: 6
Failed: 0
Inter-run delay: 30 seconds
Wazuh evidence padding: 10 seconds
```

Reference command:

```powershell
.\scripts\run-dataset-batch.ps1 `
  -Scenarios Benign,LightDos `
  -RunsPerScenario 3 `
  -Intensities Low `
  -Randomize `
  -InterRunDelaySeconds 30
```

Confirmed runs:

| Run ID | Scenario | Label | Intensity | Actor profile | Status | Verification | Export |
|---|---|---|---|---|---|---|---|
| `benign-20260604T182359Z-001` | `Benign` | `Benign` | `Low` | `normal_user` | completed | passed | exported |
| `benign-20260604T182359Z-002` | `Benign` | `Benign` | `Low` | `careless_user` | completed | passed | exported |
| `benign-20260604T182359Z-003` | `Benign` | `Benign` | `Low` | `demo_operator` | completed | passed | exported |
| `lightdos-20260604T182359Z-004` | `LightDos` | `DoS` | `Low` | `attacker_single_ip` | completed | passed | exported |
| `lightdos-20260604T182359Z-005` | `LightDos` | `DoS` | `Low` | `attacker_noisy` | completed | passed | exported |
| `lightdos-20260604T182359Z-006` | `LightDos` | `DoS` | `Low` | `attacker_single_ip` | completed | passed | exported |

All six runs received Wazuh archive/alert slices and evidence summaries. LightDos summaries include `/home/ubuntu/web-lab/logs/webapp.log` and `/var/log/nginx/access.log`.

The 30-second delay reduces evidence from adjacent controlled runs, but Wazuh windows still contain normal background events such as journald, authentication, and system activity. Treat Wazuh alerts as contextual evidence, not ground-truth labels, and preserve location/agent provenance during normalization.

## Verification commands

Auth logs:

```powershell
multipass exec auth-server -- tail -n 40 /home/ubuntu/auth-lab/logs/auth.log
```

Web logs:

```powershell
multipass exec web-server -- tail -n 40 /home/ubuntu/web-lab/logs/webapp.log
```

nginx access logs:

```powershell
multipass exec web-server -- sudo tail -n 40 /var/log/nginx/access.log
```

Database latest login attempts:

```powershell
multipass exec db-server -- sudo -u postgres psql -d xdr_lab -c "SELECT event_type, username, source_ip, success, reason, timestamp FROM login_attempts ORDER BY id DESC LIMIT 20;"
```

Database latest web events:

```powershell
multipass exec db-server -- sudo -u postgres psql -d xdr_lab -c "SELECT event_type, username, source_ip, path, suspicious, reason, timestamp FROM web_events ORDER BY id DESC LIMIT 20;"
```

## Windowing, labelling, and model-ready handoff

Build window-level rows from existing verified evidence:

```powershell
.\scripts\build-windowed-dataset.ps1 `
  -BatchManifestPath "exports\batches\<batch-id>\batch-manifest.json" `
  -WindowSeconds 5 `
  -StepSeconds 5 `
  -IncludeWazuh
```

Generate manual labelling candidates:

```powershell
.\scripts\build-labelling-candidates.ps1 `
  -BatchManifestPath "exports\batches\<batch-id>\batch-manifest.json"
```

Create a leakage-reduced handoff table:

```powershell
.\scripts\build-model-ready-dataset.ps1 `
  -BatchManifestPath "exports\batches\<batch-id>\batch-manifest.json"
```

Create a v2 plan without running traffic:

```powershell
.\scripts\new-v2-dataset-plan.ps1 -OutputPlanName "dataset-v2-dryrun"
```

Avoid label leakage in first baseline ML. Do not use scenario names, sublabels, variants, actor profiles, run IDs, paths, raw logs, string IP addresses, or direct attack-mode metadata as input features.

## Explanation labelling layer

The next explanation-layer scripts should create new outputs only under:

```text
exports\explanation-labels
exports\model-ready-explanation
```

Do not modify existing generated dataset outputs, raw evidence folders, model-ready files, windowed files, quality summaries, batch manifests, or verified-run evidence.

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

Evidence score:

- `0` = irrelevant
- `1` = weak supporting evidence
- `2` = useful supporting evidence
- `3` = strong evidence that should appear in the incident graph/report

Every explanation label row should include `label_source`, `label_confidence`, `label_reason`, and `needs_human_review`. Allowed `label_source` values are `rule_based`, `codex_assisted`, and `human_reviewed`.

These explanation labels are AI-assisted / rule-assisted weak labels, not perfect manually verified human ground truth.

Quality rules:

- Benign windows should normally be `baseline`.
- For `DoS_DDoS` runs, the first high request-rate or burst-search window should be `burst_onset`.
- Later high request-rate windows should be `sustained_pressure`.
- High request volume plus increased `response_time_ms`, nginx errors, 5xx status, or failed health checks can be `service_stress`.
- `service_degradation` must only be used when explicit degradation evidence exists, such as 5xx status, failed health check, timeout, service unavailable, connection refused, nginx error, or severe latency spike.
- If a `DoS_DDoS` window only shows many successful requests, label it `burst_onset`, `sustained_pressure`, or `service_stress`, not `service_degradation`.
- nginx/webapp burst request events should usually be `representative_burst_request` or `webapp_request_completion` with score `3`.
- Wazuh archive events that mirror nginx/webapp HTTP evidence should usually be `wazuh_confirmation` with score `2`.
- Wazuh SSH/PAM/sudo/session/system events should usually be `irrelevant` with score `0` unless they directly support the service-stress incident story.
- Single-source `AttackerHostLightDos` should not be labelled as `distributed_source_evidence` or true DDoS unless multiple visible source IPs exist.
- Do not invent evidence that is not present in raw logs.
- Mark unclear, low-confidence, and degradation-related rows with `needs_human_review=true`.
