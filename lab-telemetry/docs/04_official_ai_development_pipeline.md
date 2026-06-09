| **Prepared for**    | Coding Fest 2026 / UTS Honours-level team         |
|---------------------|---------------------------------------------------|
| **Prepared by**     | Project team - Explainable AI-Driven XDR Platform |
| **Document status** | Official scope-aligned working document           |

*This version adopts the official incident taxonomy for the system scope: Malware Attacks, Unauthorized Access, Data Breaches, and Denial of Service.*

# 1. Pipeline purpose

The AI pipeline converts Wazuh-linked telemetry and controlled lab activity into reproducible datasets, deployable models, explanation artifacts, and stable inference APIs. It is not a standalone notebook exercise. It is a product workstream that must remain aligned to the incident taxonomy, the backend schema, and the analyst experience exposed in the application.

# Official Incident Taxonomy

The project scope is now defined by four top-level incident classes. Previous attack scenarios are retained only as **lab exemplars and validation cases**, not as the primary scope statement.

| **Incident Class**                                                                                                 | **Representative SOC Incidents**                                                                          | **Primary ATT&CK Tactics**                                                                                                                                                                                                                                                                                                                                          |
|--------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [**Malware Attacks**](https://www.sans.org/security-resources/glossary-of-terms/incident-response)                 | Malicious execution; persistence creation; command-and-control communications                             | [Execution](https://attack.mitre.org/tactics/TA0002/); [Persistence](https://attack.mitre.org/tactics/TA0003/); [Defense Evasion](https://attack.mitre.org/tactics/TA0005/); [Command and Control](https://attack.mitre.org/tactics/TA0011/)                                                                                                                        |
| [**Unauthorized Access**](https://www.sans.org/security-resources/glossary-of-terms/incident-response)             | Credential harvesting; brute force; valid-account abuse; account takeover progression                     | [Initial Access](https://attack.mitre.org/tactics/TA0001/); [Credential Access](https://attack.mitre.org/tactics/TA0006/); [Persistence](https://attack.mitre.org/tactics/TA0003/)                                                                                                                                                                                  |
| [**Data Breaches**](https://www.sans.org/security-resources/glossary-of-terms/data-breach)                         | Privilege escalation; lateral movement; web exploitation; internal discovery; collection and exfiltration | [Initial Access](https://attack.mitre.org/tactics/TA0001/); [Privilege Escalation](https://attack.mitre.org/tactics/TA0004/); [Discovery](https://attack.mitre.org/tactics/TA0007/); [Lateral Movement](https://attack.mitre.org/tactics/TA0008/); [Collection](https://attack.mitre.org/tactics/TA0009/); [Exfiltration](https://attack.mitre.org/tactics/TA0010/) |
| [**Denial of Service (DoS) Attacks**](https://www.sans.org/security-resources/glossary-of-terms/incident-response) | Network flooding; service exhaustion; outage-inducing resource stress                                     | [Impact](https://attack.mitre.org/tactics/TA0040/)                                                                                                                                                                                                                                                                                                                  |

Operational note: concrete demonstrations such as credential stuffing to ATO, PowerShell-driven persistence, SQL injection, insider exfiltration, and DDoS remain in scope as scenario implementations nested under these four classes.

# 2. AI design decision introduced by this revision

The incident taxonomy is now organized around four official incident classes rather than a flat list of scenarios. Accordingly, the AI pipeline adopts a hierarchical structure: a primary incident-class classifier predicts Benign, Malware Attack, Unauthorized Access, Data Breach, or DoS; secondary support models and rule logic then enrich class-specific interpretation such as ATO transition, persistence evidence, exfiltration risk, or SQLi likelihood.

# 3. Mandatory AI functions

| **AI capability**                 | **Purpose in platform**                                                                                               | **Release-1 priority** |
|-----------------------------------|-----------------------------------------------------------------------------------------------------------------------|------------------------|
| Main incident-class classifier    | Classify windowed behavior into Benign, Malware, Unauthorized Access, Data Breach, or DoS.                            | Required               |
| Unauthorized-access support logic | Strengthen interpretation of credential harvesting, brute-force bursts, valid-account abuse, and ATO transitions.     | Recommended            |
| Malware support logic             | Score execution, persistence, and command-and-control evidence, especially on the Windows endpoint.                   | Recommended            |
| Breach support logic              | Support interpretation of privilege escalation, lateral movement, SQLi/web exploitation, discovery, and exfiltration. | Recommended            |
| DoS support logic                 | Model or threshold service-stress and outage-inducing traffic patterns.                                               | Optional but useful    |
| Explainability service            | Produce local and global explanation outputs for each deployed supervised model.                                      | Required               |

# 4. Model inventory

Release 1 should prefer a disciplined set of models with direct product utility.

| **Model** | **Priority** | **Targets**                    | **Notes**                                                                                |
|-----------|--------------|--------------------------------|------------------------------------------------------------------------------------------|
| Model A   | Required     | Main 5-class window classifier | Primary supervised model powering dashboard counts and incident detail predictions.      |
| Model B   | Recommended  | Unauthorized-access support    | Focuses on credential bursts, suspicious success-after-fail transitions, and ATO hints.  |
| Model C   | Recommended  | Malware support                | Focuses on PowerShell, suspicious process lineage, persistence, and C2 signals.          |
| Model D   | Recommended  | Breach support                 | Focuses on SQLi/web exploitation, discovery, lateral movement, and exfiltration signals. |
| Model E   | Optional     | DoS/service stress             | Can remain threshold-driven if labeled data is too limited.                              |

# 5. Sequence rule

The AI team works in parallel with the platform team. It should not wait until the full application is complete, and it should not diverge into an isolated notebook track with incompatible schemas. Baseline models are integrated early, then improved through better data, better feature engineering, and stronger error analysis.

# 6. Ordered AI work program

## Phase 1 - Taxonomy lock, labels, and governance

- Freeze class labels to Benign, Malware, Unauthorized Access, Data Breach, and DoS.

- Define sublabels or evidence tags for exemplar behaviors such as ATO transition, persistence, SQLi, exfiltration, and service flood.

- Create dataset register with source, scenario, labeling method, limitations, and license note.

## Phase 2 - Public-source acquisition and lab planning

- Use public datasets only where they strengthen agreed classes, especially for traffic anomalies or supporting auth patterns.

- Do not prioritize unrelated datasets that do not strengthen the official incident taxonomy.

- Prepare runbooks for each exemplar scenario with timing, commands, targets, rollback, and expected evidence.

## Phase 3 - Lab telemetry collection

- Validate auth, endpoint, web, DB, and service telemetry before attacks begin.

- Collect benign background activity with the same rigor as attack activity.

- Execute repeated runs with parameter variation so models learn patterns rather than a single script.

## Phase 4 - Raw export and normalization alignment

- Export raw Wazuh evidence per run and preserve source fidelity.

- Parse records into the same normalized event schema used by the application.

- Attach run IDs, host roles, user context, and label metadata to each event.

## Phase 5 - Windowing and dataset construction

- Choose one primary time-window size for release 1 and evaluate alternatives only after baseline integration.

- Aggregate counts, transitions, and cross-source signals into feature-ready windows.

- Split data by whole runs or sessions to prevent leakage.

## Phase 6 - Feature engineering by incident class

- Unauthorized Access: failed-burst size, username diversity, source-IP concentration, success-after-fail, login novelty, downstream access markers.

- Malware: suspicious process lineage, encoded command indicators, persistence markers, unusual connections, Sysmon event ratios.

- Data Breach: web exploitation markers, unusual queries, dump/export actions, internal discovery, lateral movement, outbound transfer indicators.

- DoS: request rate, unique-source ratio, error spikes, service degradation, and utilization pressure.

## Phase 7 - Baseline training and evaluation

- Train simple baseline models first, such as Random Forest or gradient-boosted trees.

- Evaluate on held-out runs, not random rows, and report class-level metrics.

- Investigate false positives from ordinary admin, login, maintenance, and traffic behaviors.

## Phase 8 - Explainability and packaging

- Generate SHAP or equivalent local explanations for every deployed supervised model.

- Create global summaries by incident class so the frontend can show recurring patterns.

- Package models, schemas, and explanation references with explicit versioning.

## Phase 9 - Integration and operational validation

- Expose stable inference APIs returning class, confidence, model version, and explanation references.

- Integrate the baseline model immediately once normalized data is usable.

- Validate end-to-end behavior from lab execution to dashboard display.

# 7. Source strategy by incident class

| **Incident class**  | **Best source**                            | **Why**                                                                                               | **Labeling note**                                             |
|---------------------|--------------------------------------------|-------------------------------------------------------------------------------------------------------|---------------------------------------------------------------|
| Unauthorized Access | Lab first, optional auth datasets          | Need direct failed-burst to compromise progression tied to the monitored auth service.                | Retain run boundaries and actor identifiers.                  |
| Malware Attacks     | Lab first                                  | Need Sysmon-rich endpoint evidence and persistence artifacts aligned to the platform.                 | Keep command line, process lineage, registry/task evidence.   |
| Data Breaches       | Lab first, optional selective augmentation | Need web, DB, and transfer evidence aligned to the same hosts and users.                              | Preserve multi-host sequences and exfiltration timing.        |
| DoS Attacks         | Hybrid: public traffic plus lab runs       | Public datasets provide scale; lab runs provide service-impact timing and platform-specific evidence. | Normalize packet-heavy sources into event or aggregated form. |

# 8. Model-to-product mapping

| **Output**                        | **Consumed by**             | **Visible in app**                                | **User value**                                         |
|-----------------------------------|-----------------------------|---------------------------------------------------|--------------------------------------------------------|
| Main class prediction             | Dashboard and incident page | Counters, incident detail, correlation enrichment | Shows likely incident class and confidence.            |
| Unauthorized-access support score | Auth-related incident views | ATO or credential-abuse hints                     | Highlights suspicious identity progression.            |
| Malware support score             | Endpoint incident views     | Execution and persistence evidence panel          | Supports analyst understanding of compromise behavior. |
| Breach support score              | DB/web incident views       | SQLi, lateral movement, exfiltration indicators   | Clarifies how a breach developed.                      |
| DoS stress score                  | Service-health logic        | DoS and outage widgets                            | Shows likely degradation caused by flood behavior.     |
| Explanation payloads              | Explanation panel           | Local reasons and class-level patterns            | Builds analyst trust in predictions.                   |

# 9. Pipeline boundaries

- Do not expand the AI scope into unrelated domains that do not strengthen the official incident taxonomy.

- Do not replace rule-based causal reasoning with an opaque graph model in release 1.

- Do not package any model whose input schema, label mapping, and user-facing purpose are undocumented.

- Do not optimize only for overall accuracy; class-level visibility and operational realism matter more.

# 10. Exit criteria

- A reproducible dataset pipeline rebuilds normalized, windowed datasets from Wazuh-linked telemetry and run metadata.

- At least one baseline class model is integrated early, and all deployed models map to visible product behavior.

- Class-level evaluation exists for Benign, Malware, Unauthorized Access, Data Breach, and DoS.

- Explanation outputs exist for every deployed supervised model.

- Model artifacts, feature schemas, and API contracts are versioned and stable for the demo build.
