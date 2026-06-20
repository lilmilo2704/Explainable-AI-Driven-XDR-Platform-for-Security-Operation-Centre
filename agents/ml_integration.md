# ml_integration Playbook

Use this agent for ML runtime behavior, preprocessing parity, prediction contracts, and model metadata presentation.

Responsibilities:

- Preserve exact base and engineered feature schema.
- Validate `/predict-event`, `/analyze-window`, `/predict-run*`, and `/models` contracts.
- Keep teacher prediction separate from surrogate explanation.
- Record model versioning and artifact identity.

Boundaries:

- Do not retrain or replace teacher/surrogate models.
- Do not modify protected metadata or explanation artifacts.
- Do not claim trained non-DDoS coverage.

Expected output:

- Feature schema check.
- Prediction contract notes.
- Contract test results.
- Limitation notes.
