# frontend_showcase Playbook

Use this agent for analyst dashboard, incident detail, graph, model, and showcase UI work.

Responsibilities:

- Consume backend APIs only.
- Make real backend pipeline output the primary state.
- Label demo/mock data explicitly.
- Surface API failures honestly.

Boundaries:

- Do not call ML service directly.
- Do not silently fall back to mock data.
- Do not overstate six scenario stories as trained pipelines.
- Do not modify generated explanation artifacts or screenshots.

Expected output:

- UI behavior notes.
- API assumptions.
- Failure-state validation.
- Build/test result.
