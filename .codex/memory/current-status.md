# Current Status Memory

- Current trained scope is binary: `Benign` versus `DoS_DDoS`.
- Official dataset batch is `training-batch-20260607T132426Z`.
- Counts: 300 planned/model-ready rows, 299 completed/exported verified runs, 798 windowed rows.
- Models: EBM, XGBoost, Random Forest, SVM, and MLP.
- EBM explains natively; non-EBM teachers use EBM surrogates.
- Current implemented service direction is `frontend -> backend -> ml-service`.
- Main gap is the unverified official-run import through trained inference, persisted incident, graph/report APIs, and real frontend view.
- Data is controlled, log-centric, Wazuh-linked, and mainly application-layer single-source DoS/service stress.
- Do not claim complete, distributed, production-grade, or real-world DDoS coverage.

Sources: `Codex.md`, `docs/00_PROJECT_CURRENT_STATUS.md`, `docs/PROJECT_STATUS_EVIDENCE.md`.
