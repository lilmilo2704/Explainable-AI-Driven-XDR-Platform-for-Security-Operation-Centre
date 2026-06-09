# Project Context Summary - Coding Fest 2026 Explainable XDR/SIEM Lab

## One-sentence purpose

Prepare a log-centric, Wazuh-linked XDR dataset and prototype pipeline for detecting and explaining application-layer DoS/DDoS/service-stress incidents using server-side logs, web application logs, nginx logs, Wazuh archives, Wazuh alerts, and windowed behaviour features.

## Product idea

The long-term project is an Explainable AI-Driven XDR Platform for Security Operation Centre teams. The current repository responsibility is narrower and more concrete: prepare a controlled Wazuh-linked application-layer DoS/service-stress dataset and build the next explanation layer so the system can explain what happened, which stage occurred, and which logs prove each stage.

The long-term platform architecture is:

```text
Lab endpoints and services
  -> Wazuh agents and Wazuh Server
  -> raw alerts/logs
  -> normalization service
  -> structured events
  -> event grouping and correlation
  -> incident objects and timelines
  -> ML inference and explainability
  -> causal graph / attack story
  -> SOC dashboard and case workflow
```

## Official incident taxonomy

The official scope is not an unbounded set of individual attacks. It is organized around four incident classes:

| Incident class | Representative lab exemplars |
|---|---|
| Malware Attacks | suspicious PowerShell, persistence, command-and-control style telemetry |
| Unauthorized Access | credential stuffing, brute force, valid-account abuse, ATO progression |
| Data Breaches | SQLi-style web exploitation, discovery, collection, exfiltration-style telemetry |
| Denial of Service | controlled web-service flood, service stress, request-volume spike |

The current DB/Auth/Web/Wazuh lab supports Benign, Unauthorized Access, Data Breach/SQLi-style, bounded `LightDos`, and `AttackerHostLightDos` telemetry. The confirmed current direction emphasizes application-layer DoS/DDoS-style service-stress detection and explanation from logs without packet capture. Malware and broad multi-incident detection are not the current focus.

Important dataset positioning: the current official dataset is a controlled Wazuh-linked application-layer DoS/service-stress dataset. It must not be described as a complete real-world DDoS benchmark, and `AttackerHostLightDos` must not be called true DDoS unless multiple visible source IPs exist in victim logs.

## Current practical lab

Current Multipass VMs:

- `auth-server`
- `db-server`
- `web-server`
- `wazuh-server`

The servers use bridged DHCP addresses. Current IPs are resolved dynamically by the automation.

Current services:

- `db-server`: PostgreSQL database `xdr_lab`
- `auth-server`: FastAPI Auth API as `auth-lab.service`
- `web-server`: FastAPI Web app as `web-lab.service`
- `web-server`: nginx reverse proxy exposing the web app on port 80
- `wazuh-server`: Wazuh manager, indexer, dashboard, and Filebeat

Current dataset architecture:

- `web-server` is the primary HTTP DoS/service-stress target.
- `auth-server` is optional/supporting HTTP and login evidence.
- `db-server` is a backend dependency, not a direct DoS target.
- `wazuh-server` is the SIEM/XDR evidence collector.

Current database tables:

- `users`
- `login_attempts`
- `web_events`

Current logs:

- `/home/ubuntu/auth-lab/logs/auth.log`
- `/home/ubuntu/web-lab/logs/webapp.log`
- `/var/log/nginx/access.log`
- `/var/log/nginx/error.log`
- `/var/ossec/logs/archives/archives.json`
- `/var/ossec/logs/alerts/alerts.json`

## Completed milestones

- Multipass DB/Auth/Web foundation.
- PostgreSQL installed and remotely reachable by Auth/Web.
- Auth Server FastAPI login API created.
- Auth JSON logs created.
- Auth systemd service enabled and active.
- Web Server FastAPI routes created: `/`, `/health`, `/search`, `/login`, `/admin`.
- Web JSON logs created.
- Web systemd service enabled and active.
- nginx reverse proxy configured.
- Linked Web/Auth evidence verified.
- `scripts/start-and-check-lab.ps1` created and confirmed working from `C:\D\xdr-lab-telemetry`.
- Controlled telemetry, cache, verification, verified-run export, and batch automation completed.
- Wazuh all-in-one server installed; agents active on Auth/Web/DB.
- Wazuh archive logging and custom localfile collection confirmed.
- Wazuh archive/alert evidence exporter completed using local transferred cache files.
- Service-impact web logging completed with status, method, path, endpoint, source, user-agent, and duration fields.
- LightDos verification checks completed with old-run WARN compatibility.
- Batch inter-run delay completed and validated to reduce padded evidence-window overlap.
- Reference separated Wazuh-linked batch `training-batch-20260604T182359Z` completed with six verified/exported runs.
- Dataset quality summary builder completed.
- ML feature table builder completed.
- Raw-content ML feature export completed.
- Official 300-row dataset prepared from `training-batch-20260607T132426Z`.
- Wazuh evidence export bug fixed for compressed `.json.gz` files and local-timezone date candidates.
- Fast Wazuh batch exporter created and used successfully.
- Windowed dataset builder completed.
- Model-ready run-level dataset builder completed.
- Clean portable dataset release packaged.
- Laptop-specific paths such as `C:\D\xdr-lab-telemetry` removed from the clean release.
- Raw evidence folder count validated as 299 because `benign-20260607T132426Z-043` is incomplete/excluded.
- CSV row counts validated as 300 run-level rows and 798 window rows.

## Current dataset status

The evidence collection pipeline is complete through labelled generation, local verification/export, Wazuh evidence slicing, service-impact logging, separated batch collection, dataset quality summaries, ML feature tables, and raw-content feature exports.

Official current dataset:

```text
Batch ID: training-batch-20260607T132426Z
Clean release: exports\dataset-releases\coding-fest-2026-xdr-dataset-training-batch-20260607T132426Z-clean\
Clean zip: exports\dataset-releases\coding-fest-2026-xdr-dataset-training-batch-20260607T132426Z-clean.zip
```

| Scenario | Count | ML label |
|---|---:|---|
| `Benign` | 100 | `Benign` |
| `LightDos` | 100 | `DoS_DDoS` |
| `AttackerHostLightDos` | 100 | `DoS_DDoS` |

Known dataset facts:

- 300 tabular runs.
- 200 `DoS_DDoS`-labelled runs total.
- 798 windowed rows.
- 300 model-ready run-level rows.
- 299 raw verified-run evidence folders.
- `benign-20260607T132426Z-043` is the known incomplete run.
- `benign-20260607T132426Z-043` failed verification/export and is intentionally missing from raw evidence.
- For clean supervised training, use `is_clean_supervised_training_candidate == True`.

Included artifacts:

- `features.csv` and `features.json`
- `features-with-raw-content.csv` and `features-with-raw-content.json`
- `quality-summary.csv` and `quality-summary.json`
- `batch-manifest.json`
- verified run folders for 299 completed/exported runs
- Wazuh archive/alert slices and evidence summaries
- model-ready run-level export with leakage/provenance fields removed

Honest assessment:

- usable for baseline ML handoff when clean candidate filtering is respected
- suitable for explanation-layer work because raw evidence and windowed rows exist
- not a complete real-world or public-quality DDoS benchmark
- controlled lab-generated data rather than production traffic
- single-source DoS/service-stress rather than true distributed DDoS

## Current next stage

The next dataset-layer stage is explanation-labelling. Do not modify the existing dataset outputs. Create new outputs only under `exports\explanation-labels` and `exports\model-ready-explanation`.

The explanation layer should support:

- stage classification
- evidence attribution
- incident storyline graph
- SOC-style report generation

New labels to add:

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

Every generated label row should include `label_source`, `label_confidence`, `label_reason`, and `needs_human_review`. Explanation labels are AI-assisted / rule-assisted weak labels, not perfect manually verified human ground truth.

The explanation layer should preserve:

- `run_id`, scenario labels, actor profile, and intensity
- metadata and evidence-window boundaries
- local source paths and Wazuh provenance
- request-rate, repeated-path, source-ratio, status-code, latency, and duration features
- raw evidence references for review

Immediate tooling tasks:

1. Create `scripts\build-explanation-labels.ps1`.
2. Create `scripts\build-model-ready-explanation-datasets.ps1`.
3. Create `scripts\build-explanation-label-quality-report.ps1`.
4. Package a new explanation-enriched release after labels are built and checked.

Attacker-VM work, packet capture, custom Wazuh rules, public packet/flow dataset merging, true multi-source DDoS, and AI training remain outside this immediate stage unless explicitly requested.

## Wazuh role

Wazuh is installed and working as the telemetry and evidence-provenance layer. Controlled run metadata remains the ground-truth label source; Wazuh alerts are optional contextual features, not labels or final detection logic.

## Do Not Do

- Do not train models yet.
- Do not run large batches automatically.
- Do not add packet capture.
- Do not claim DDoS unless multiple visible source IPs exist in victim logs.
- Do not fake source IPs.
- Do not target external systems.
- Do not rely on Wazuh alerts as ground truth labels.
- Do not directly merge public packet/flow datasets into this Wazuh lab dataset without a separate external-normalized layer.
- Do not modify existing generated dataset outputs while building explanation labels.
- Do not invent evidence that is not present in the raw logs.
