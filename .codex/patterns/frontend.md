# Frontend Patterns

- Frontend calls backend only. It must not call the ML service directly.
- Primary dashboard and incident views should use real backend pipeline output.
- Demo/mock data is allowed only when clearly labelled as demo or mock.
- Failed API calls must surface an explicit failure state, not silently fall back.
- Preserve analyst clarity: show evidence provenance, prediction source, explanation source, and confidence context.
- Display current trained scope honestly: `Benign` vs `DoS_DDoS`.
- Broader incident stories must be labelled as demo/keyword fallback unless backed by trained pipelines.
- Model pages must distinguish teacher prediction from surrogate explanation.
