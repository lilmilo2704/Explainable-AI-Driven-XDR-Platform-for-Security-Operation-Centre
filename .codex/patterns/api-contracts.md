# API Contract Patterns

- Keep contracts typed, explicit, and versioned when adding or changing payloads.
- Preserve service direction: frontend calls backend; backend calls ML service.
- Backend should validate request payloads before persistence or ML calls.
- ML contract responses must distinguish teacher prediction from surrogate explanation.
- Include model name, model version or artifact identity, schema version, and feature set version in prediction payloads.
- Represent real, demo, loading, and failure states explicitly. Do not silently replace failed API calls with mock data.
- Avoid fabricated metrics. UI metrics must trace to backend, ML metadata, or clearly labelled demo data.
- Any API/schema change requires a plan under `docs/tasks/` and contract documentation.
