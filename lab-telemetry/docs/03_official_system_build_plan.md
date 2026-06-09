| **Prepared for**    | Coding Fest 2026 / UTS Honours-level team         |
|---------------------|---------------------------------------------------|
| **Prepared by**     | Project team - Explainable AI-Driven XDR Platform |
| **Document status** | Official scope-aligned working document           |

*This version adopts the official incident taxonomy for the system scope: Malware Attacks, Unauthorized Access, Data Breaches, and Denial of Service.*

# 1. Delivery intent

This build plan is an execution guide, not a concept note. It assumes the platform is a full-stack application that embeds Wazuh as the telemetry and alerting layer, while the custom services provide normalization, hybrid detection, incident correlation, explicit causal reasoning, explainability, response guidance, and case workflow. All workstreams are aligned to the official four-class incident taxonomy.

# Official Incident Taxonomy

The project scope is now defined by four top-level incident classes. Previous attack scenarios are retained only as **lab exemplars and validation cases**, not as the primary scope statement.

| **Incident Class**                                                                                                 | **Representative SOC Incidents**                                                                          | **Primary ATT&CK Tactics**                                                                                                                                                                                                                                                                                                                                          |
|--------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [**Malware Attacks**](https://www.sans.org/security-resources/glossary-of-terms/incident-response)                 | Malicious execution; persistence creation; command-and-control communications                             | [Execution](https://attack.mitre.org/tactics/TA0002/); [Persistence](https://attack.mitre.org/tactics/TA0003/); [Defense Evasion](https://attack.mitre.org/tactics/TA0005/); [Command and Control](https://attack.mitre.org/tactics/TA0011/)                                                                                                                        |
| [**Unauthorized Access**](https://www.sans.org/security-resources/glossary-of-terms/incident-response)             | Credential harvesting; brute force; valid-account abuse; account takeover progression                     | [Initial Access](https://attack.mitre.org/tactics/TA0001/); [Credential Access](https://attack.mitre.org/tactics/TA0006/); [Persistence](https://attack.mitre.org/tactics/TA0003/)                                                                                                                                                                                  |
| [**Data Breaches**](https://www.sans.org/security-resources/glossary-of-terms/data-breach)                         | Privilege escalation; lateral movement; web exploitation; internal discovery; collection and exfiltration | [Initial Access](https://attack.mitre.org/tactics/TA0001/); [Privilege Escalation](https://attack.mitre.org/tactics/TA0004/); [Discovery](https://attack.mitre.org/tactics/TA0007/); [Lateral Movement](https://attack.mitre.org/tactics/TA0008/); [Collection](https://attack.mitre.org/tactics/TA0009/); [Exfiltration](https://attack.mitre.org/tactics/TA0010/) |
| [**Denial of Service (DoS) Attacks**](https://www.sans.org/security-resources/glossary-of-terms/incident-response) | Network flooding; service exhaustion; outage-inducing resource stress                                     | [Impact](https://attack.mitre.org/tactics/TA0040/)                                                                                                                                                                                                                                                                                                                  |

Operational note: concrete demonstrations such as credential stuffing to ATO, PowerShell-driven persistence, SQL injection, insider exfiltration, and DDoS remain in scope as scenario implementations nested under these four classes.

# 2. Build principles

- Build the product skeleton first; do not wait for perfect models before establishing platform contracts.

- Treat Wazuh as infrastructure, not the main user-facing product.

- Keep first release scope disciplined: prioritize the four incident classes and their exemplar lab scenarios only.

- Integrate baseline intelligence early; iterate behind stable APIs rather than rebuilding interfaces late.

- Keep the causal reasoning layer rule-based in release 1 for transparency, explainability, and delivery realism.

# 3. First-release functional baseline

| **Function**                               | **Minimum release-1 behavior**                                                         | **Scope alignment** |
|--------------------------------------------|----------------------------------------------------------------------------------------|---------------------|
| Endpoint onboarding and asset registration | Generate agent install commands, tag host roles, verify health, and show asset status. | All                 |
| Telemetry ingestion                        | Pull Wazuh evidence into staging and normalized stores with raw-source traceability.   | All                 |
| Incident creation                          | Group evidence into structured incident objects with timeline support.                 | All                 |
| Hybrid detection                           | Display Wazuh evidence alongside model predictions and confidence.                     | All                 |
| Graph reasoning                            | Show at least one evidence-backed directed causal graph for each incident class.       | All                 |
| Explainability                             | Display top indicators and justification text in the incident view.                    | All ML-backed paths |
| Response guidance and cases                | Create cases, assign owners, add notes, and issue analyst recommendations.             | All                 |

# 4. Service architecture

### frontend-web

React investigation console for alerts, incidents, graphs, explanations, assets, and cases.

### api-backend

FastAPI application exposing analysts, incidents, assets, cases, explanations, and administration endpoints.

### wazuh-connector

Imports alerts and related telemetry from the embedded Wazuh layer.

### normalization-service

Maps imported records into the internal event schema.

### correlation-engine

Clusters normalized events into incident objects and timelines.

### causal-reasoning-engine

Applies rule-based edge inference and confidence scoring to timelines.

### ml-inference-service

Hosts incident-class and support-model inference endpoints.

### xai-service

Generates and caches explanation payloads for predictions.

### recommendation-service

Maps scenario context and confidence to analyst guidance.

### case-service

Owns case workflow, notes, ownership, and closure state.

### postgres and queue

Persist structured entities and schedule jobs.

### embedded-wazuh-stack

Manager, indexer, and supporting services used as background infrastructure.

# 5. Ordered build program

| **Stage** | **Primary emphasis**     | **Parallel work**                                        | **Exit condition**                                                                       |
|-----------|--------------------------|----------------------------------------------------------|------------------------------------------------------------------------------------------|
| A         | Foundation               | Dataset register, schema design, first raw samples       | Running Docker stack with frontend, backend, database, and embedded Wazuh health checks. |
| B         | Ingestion and onboarding | Lab runbooks, adapter scripts, first feature definitions | Normalized events available to both app and AI workstreams.                              |
| C         | Baseline intelligence    | First model training and explanation scaffolding         | At least one baseline model callable from the app and visible in the incident page.      |
| D         | Scenario depth           | Additional support models, graph logic, response rules   | All incident classes demonstrable end-to-end.                                            |
| E         | Hardening                | Threshold tuning, seeded demos, export-ready screens     | Reliable demo build with documented limitations and metrics.                             |

# 6. Detailed missions by phase

## Phase 1 - Contracts and infrastructure

- Freeze the official incident taxonomy and confirm exemplar scenarios per class.

- Define asset, raw-event, normalized-event, prediction, incident, graph, recommendation, and case schemas.

- Prepare monorepo structure, Docker Compose, service health checks, and environment templates.

## Phase 2 - Embedded Wazuh and asset onboarding

- Stand up the embedded Wazuh stack and verify agent connectivity from lab endpoints.

- Implement Add Endpoint flow and host-role tagging for auth, web, DB, Windows endpoint, and user workstation.

- Expose asset health, last seen time, and event volume in the application.

## Phase 3 - Ingestion and normalization

- Import raw alerts into staging tables while preserving source references.

- Normalize auth, endpoint, web, database, and system events into a single schema.

- Add enrichment fields such as host role, event family, scenario hints, and entity relationships.

## Phase 4 - Baseline analyst workflow

- Expose Wazuh rule evidence through the custom app.

- Create simple incident objects using time proximity and shared entities.

- Render alert and incident pages before advanced AI or graph features are complete.

## Phase 5 - AI contract and early integration

- Define stable prediction API payloads using window-based records.

- Integrate the first baseline model and display class, confidence, model version, and top indicators.

- Add explanation placeholders and persistence for model outputs.

## Phase 6 - Correlation and attack-story reconstruction

- Upgrade incident logic with shared-user, host-role, IP, process-lineage, and template-based grouping.

- Generate analyst-readable incident summaries and durable timelines.

- Allow pivots from incidents to assets, users, IPs, and raw evidence.

## Phase 7 - Explicit causal reasoning

- Build graph nodes and inferred edges from incident timelines.

- Implement labelled semantics such as enabled access, established persistence, triggered backend query, and exfiltrated via.

- Render edge explanations and confidence values in the graph view.

## Phase 8 - Response, cases, and demo preparation

- Add analyst recommendations tied to incident class and evidence profile.

- Implement case workflow with ownership, notes, and status transitions.

- Prepare seeded demo data, presentation flows, and screenshot-friendly views.

# 7. Team workstream structure

| **Workstream**                  | **Starts**                    | **Owns**                                                               | **Dependencies**    |
|---------------------------------|-------------------------------|------------------------------------------------------------------------|---------------------|
| Platform foundation             | Day 1                         | Repo, Docker, backend shell, database, frontend shell, Wazuh embedding | None                |
| Data and lab pipeline           | Day 1-3                       | Runbooks, telemetry validation, raw exports, normalization support     | Platform contracts  |
| AI baseline modeling            | When normalized samples exist | Window design, baseline classifier, explanation scaffolding            | Normalized data     |
| Correlation and graph reasoning | After schema stabilizes       | Incident logic, graph builder, edge rules                              | Normalized events   |
| Demo engineering                | After first end-to-end flow   | Scenario scripts, exports, performance tuning                          | Integrated platform |

# 8. Release-1 non-goals

- No promise of autonomous containment or full SOAR orchestration.

- No requirement that causal reasoning be machine-learned in release 1.

- No expansion into unrelated product areas beyond the official incident taxonomy and exemplar scenarios.

- No dependency on a polished cloud deployment before the academic demonstration is successful.

# 9. Exit criteria

- The custom application is the primary user-facing product and operates independently of the Wazuh dashboard for normal analyst flow.

- Each official incident class can be demonstrated in the application with matching evidence, timeline, graph, and recommendation flow.

- At least one baseline model is integrated early, and all deployed models map to visible product functions.

- Graph edges are interpretable, evidence-backed, and consistent with known lab steps.

- The build path remains architecture-first, AI-parallel, and baseline-integrated rather than notebook-first or UI-only.
