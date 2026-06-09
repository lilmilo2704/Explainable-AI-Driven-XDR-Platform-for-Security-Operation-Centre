| **Prepared for**    | Coding Fest 2026 / UTS Honours-level team         |
|---------------------|---------------------------------------------------|
| **Prepared by**     | Project team - Explainable AI-Driven XDR Platform |
| **Document status** | Official scope-aligned working document           |

*This version adopts the official incident taxonomy for the system scope: Malware Attacks, Unauthorized Access, Data Breaches, and Denial of Service.*

# 1. Executive summary

This proposal defines the project as an incident-centric XDR-SIEM research prototype for Security Operations Centre workflows. The system uses Wazuh as the telemetry and alerting substrate, while the custom platform adds event normalization, hybrid detection, incident construction, explicit causal reasoning, explainability, and analyst-facing workflow support. The revised scope replaces a loose list of individual attacks with an official taxonomy of four incident classes so that system design, data engineering, AI development, and evaluation all share one authoritative structure.

# Official Incident Taxonomy

The project scope is now defined by four top-level incident classes. Previous attack scenarios are retained only as **lab exemplars and validation cases**, not as the primary scope statement.

| **Incident Class**                                                                                                 | **Representative SOC Incidents**                                                                          | **Primary ATT&CK Tactics**                                                                                                                                                                                                                                                                                                                                          |
|--------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [**Malware Attacks**](https://www.sans.org/security-resources/glossary-of-terms/incident-response)                 | Malicious execution; persistence creation; command-and-control communications                             | [Execution](https://attack.mitre.org/tactics/TA0002/); [Persistence](https://attack.mitre.org/tactics/TA0003/); [Defense Evasion](https://attack.mitre.org/tactics/TA0005/); [Command and Control](https://attack.mitre.org/tactics/TA0011/)                                                                                                                        |
| [**Unauthorized Access**](https://www.sans.org/security-resources/glossary-of-terms/incident-response)             | Credential harvesting; brute force; valid-account abuse; account takeover progression                     | [Initial Access](https://attack.mitre.org/tactics/TA0001/); [Credential Access](https://attack.mitre.org/tactics/TA0006/); [Persistence](https://attack.mitre.org/tactics/TA0003/)                                                                                                                                                                                  |
| [**Data Breaches**](https://www.sans.org/security-resources/glossary-of-terms/data-breach)                         | Privilege escalation; lateral movement; web exploitation; internal discovery; collection and exfiltration | [Initial Access](https://attack.mitre.org/tactics/TA0001/); [Privilege Escalation](https://attack.mitre.org/tactics/TA0004/); [Discovery](https://attack.mitre.org/tactics/TA0007/); [Lateral Movement](https://attack.mitre.org/tactics/TA0008/); [Collection](https://attack.mitre.org/tactics/TA0009/); [Exfiltration](https://attack.mitre.org/tactics/TA0010/) |
| [**Denial of Service (DoS) Attacks**](https://www.sans.org/security-resources/glossary-of-terms/incident-response) | Network flooding; service exhaustion; outage-inducing resource stress                                     | [Impact](https://attack.mitre.org/tactics/TA0040/)                                                                                                                                                                                                                                                                                                                  |

Operational note: concrete demonstrations such as credential stuffing to ATO, PowerShell-driven persistence, SQL injection, insider exfiltration, and DDoS remain in scope as scenario implementations nested under these four classes.

# 2. Problem statement

Operational SOC teams face a recurring mismatch between what tools produce and what analysts actually need. SIEMs and EDR tools surface alerts, but analysts must still decide whether those alerts belong to a coherent incident, how the attack progressed, which assets were affected, and what action should be taken next. This gap becomes more severe when detections are opaque or when multiple hosts and services are involved.

The project addresses this problem by shifting from alert-centric monitoring to incident-centric reasoning. Instead of treating attacks as isolated detections, the platform organizes telemetry into incidents aligned to a formal incident taxonomy based on MITRE ATT&CK and SANS, reconstructs timelines, labels causal relationships, and explains model outputs in a manner suitable for analyst review. This helps the SOC analysts to better understand the security incidents happening, avoid wasting time on huge amount of false alarms and proceed and escalate the cybersecurity problems more efficiently.

# 3. Official project scope

## 3.1 Scope statement

The authoritative scope of the system consists of four incident classes: Malware Attacks, Unauthorized Access, Data Breaches, and Denial of Service. Each class is supported by representative SOC incidents, listed by SANS, and ATT&CK-aligned behaviors. This scope supersedes prior versions that presented concrete scenarios as the primary classification layer.

## 3.2 Lab exemplars retained for build and evaluation

| **Incident Class**  | **Lab Exemplar**                                                         | **Purpose in Evaluation**                                                                                    |
|---------------------|--------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------|
| Unauthorized Access | Credential stuffing to ATO                                               | Demonstrates identity abuse, transition from failed burst to compromise, and downstream asset access.        |
| Malware Attacks     | Encoded PowerShell plus persistence plus outbound callback               | Demonstrates execution, persistence, defense evasion indicators, and analyst explanation panels.             |
| Data Breaches       | SQL injection, insider data exfiltration, and chained multi-stage breach | Demonstrates privilege escalation, collection, lateral movement, and exfiltration reasoning across services. |
| Denial of Service   | Controlled web-service flood                                             | Demonstrates impact-focused detection, service-health analytics, and degradation visualization.              |

# 4. System architecture

The platform is structured as a layered architecture. Monitored endpoints and services generate telemetry. Wazuh agents and the embedded Wazuh stack collect alerts and baseline evidence. The backend normalizes events into a common schema, correlates them into incidents, calls the AI services for classification and explanation, applies rule-based causal reasoning, and serves the analyst dashboard. The frontend provides alerts, incidents, graphs, explanations, asset views, and case workflows within one SOC-style application.

<img src="media/image1.png" style="width:6.3in;height:3.43716in" />

*Figure 1. High-level platform architecture used as the engineering baseline for the proposal.*

## Architecture layers

### Lab and endpoint layer

Generates controlled benign and adversarial telemetry across auth, endpoint, web, database, and service-health sources.

### Embedded Wazuh layer

Collects, stores, and exposes central security telemetry and rule-based evidence.

### Application logic layer

Normalizes events, correlates incidents, reconstructs timelines, reasons over causal edges, and manages recommendations and cases.

### AI layer

Classifies behavior windows, produces risk enrichment, and generates explanation payloads for analyst review.

### Frontend layer

Presents alert, incident, graph, explanation, asset, and case views through a unified investigation interface.

# 5. Core system functions

| **Function**                           | **Description**                                                                                        | **Incident-Class Coverage**                      |
|----------------------------------------|--------------------------------------------------------------------------------------------------------|--------------------------------------------------|
| Telemetry ingestion and centralization | Collect Wazuh-managed alerts and events from Linux, Windows, web, database, auth, and service sources. | All                                              |
| Unified event normalization            | Transform raw records into one internal schema with traceable source references.                       | All                                              |
| Hybrid detection                       | Combine Wazuh rule evidence with supervised model outputs.                                             | All                                              |
| Incident correlation                   | Group events into structured incidents using time, entities, host relationships, and templates.        | All                                              |
| Incident reconstruction                | Build analyst-readable timelines and incident summaries.                                               | Unauthorized Access; Data Breaches; Malware      |
| Explicit causal reasoning              | Render labelled attack graphs with evidence-backed edge confidence.                                    | Unauthorized Access; Malware; Data Breaches; DoS |
| Explainability                         | Show feature-level reasons for predictions and human-readable justifications for causal edges.         | All ML-backed functions                          |
| Response guidance and case management  | Provide analyst actions, case creation, notes, and ownership workflows.                                | All                                              |

# 6. Methodology

### Lab construction and telemetry validation

Build the monitored lab, register agents, and confirm steady-state telemetry before any attack execution.

### Scenario execution and dataset generation

Run controlled exemplar scenarios under the four incident classes and export raw evidence linked to run identifiers and labels.

### Hybrid detection development

Train deployable models against normalized windows while preserving Wazuh rule evidence as part of the detection layer.

### Incident and causal reasoning development

Construct incident objects and directed causal graphs after normalization and correlation have stabilized.

### System integration and analyst workflow

Expose all outputs through stable backend contracts and a single frontend investigation flow.

### Evaluation

Measure detection performance, latency, incident quality, causal-edge correctness, and analyst usefulness.

# 7. Innovation and research contribution

The main contribution is not only an explainable detector, but a disciplined incident-centric platform architecture. The project unifies four elements that are often treated separately: telemetry engineering, incident construction, AI-assisted detection, and causal analyst reasoning. The most distinctive innovation is the explicit causal reasoning layer that explains how one stage enabled the next, moving the system beyond flat alert aggregation.

# 8. Evaluation framework

| **Dimension**            | **Metrics**                                                                          | **Interpretation**                                                                     |
|--------------------------|--------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------|
| Detection quality        | Accuracy, precision, recall, F1, per-class confusion                                 | Shows whether the system distinguishes benign activity from the four incident classes. |
| Operational latency      | Ingestion, inference, explanation, graph-generation, and incident-generation latency | Shows whether the platform remains usable during investigations.                       |
| Incident quality         | Timeline coherence, evidence coverage, incident completeness                         | Shows whether grouped incidents are meaningful rather than noisy clusters.             |
| Causal reasoning quality | Edge correctness, stage coverage, explanation usefulness                             | Shows whether the graph expresses attack progression credibly.                         |

# 9. Feasibility and delivery discipline

The project is feasible because the architecture is modular, the first release is tightly bounded, and baseline intelligence can be integrated early. The team does not need to finish every model before it can show a credible end-to-end system. Open-source components such as Wazuh, Sysmon, PostgreSQL, FastAPI, React, and common Python ML libraries are sufficient for the required scale.

# 10. Conclusion

This revised proposal gives the project one consistent scope statement, one architecture story, and one delivery logic. By defining the system around a formal incident taxonomy and by treating older scenarios as exemplars rather than competing scope statements, the project becomes more professional, more defensible, and easier for a strong team to execute at honours level.
