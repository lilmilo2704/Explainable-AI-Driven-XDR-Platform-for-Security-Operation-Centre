# Evidence Provenance Patterns

- Preserve raw evidence provenance from Wazuh archives, Wazuh alerts, nginx, webapp, auth logs, and run metadata.
- Store or reference run ID, source file, line/event identifier, timestamp window, parser version, and schema version.
- Separate evidence categories:
  - observed evidence
  - derived feature
  - model inference
  - analyst recommendation
- Graph edges must include rationale, supporting evidence IDs, confidence, and whether the edge is observed or inferred.
- Do not infer causality from temporal order alone.
- Do not invent evidence absent from raw logs.
- Wazuh alerts are context, not ground-truth labels.
