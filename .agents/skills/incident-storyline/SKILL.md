---
name: incident-storyline
description: Use for incident timeline, graph, evidence provenance, inferred-edge rationale, response guidance, or SOC report narrative work.
---

# Incident Storyline

## Triggering Conditions

- Work touches incident timelines, graph nodes/edges, evidence labels, or report narrative.
- Need to distinguish observed evidence from inference or recommendation.

## Required Inputs

- Incident or run context.
- Evidence references.
- Model prediction/explanation payload.
- Desired graph/report output.

## Read First Files

1. `AGENTS.md`
2. `Codex.md`
3. `docs/00_PROJECT_CURRENT_STATUS.md`
4. `docs/PROJECT_STATUS_EVIDENCE.md`
5. `.codex/patterns/evidence-provenance.md`
6. `backend/app/services/serialization.py`
7. `frontend/src/components/CausalGraphPanel.tsx`

## Ordered Procedure

1. Classify each item as observed evidence, derived feature, model inference, or analyst recommendation.
2. Preserve run ID, source, timestamp, and parser/schema provenance.
3. Define edge rationale and confidence.
4. Link each graph or narrative claim to evidence.
5. Mark uncertain or inferred content explicitly.

## Safety Restrictions

- Do not invent evidence.
- Do not use Wazuh alerts as ground-truth labels.
- Do not infer causality from temporal order alone.
- Do not claim distributed DDoS without verified multiple source IPs.

## Validation

- Check every graph edge has support and rationale.
- Check recommendations are not presented as facts.
- Confirm frontend labels distinguish evidence categories.

## Expected Output

- Storyline/graph schema.
- Evidence mapping.
- Edge rationale.
- Report-ready narrative constraints.
