# Backend Pipeline Contracts

This document captures the current backend-owned pipeline contracts. It is narrow by design and only documents behavior that is implemented and verified in the current repository state.

## Phase 1A Official Run Verification

`POST /api/official-runs/import` is a Phase 1A verification and inventory endpoint. Despite the `import` name, it is not a durable official-run import path.

Current trained scope remains binary: `Benign` versus `DoS_DDoS`. The current evidence is controlled, log-centric, and mainly application-layer service stress / single-source DoS. Do not present this endpoint as complete, real-world, distributed, or production-grade DDoS coverage.

### Demo Protection

This endpoint is demo-protected and disabled by default. It requires server-side configuration:

```text
XDR_DEMO_IMPORT_ENABLED=true
XDR_DEMO_API_TOKEN=<secret>
```

Clients must supply the token with either:

- `Authorization: Bearer <secret>`
- `X-XDR-Demo-API-Token: <secret>`

If demo import is disabled, the token is missing, or the token is invalid, the endpoint rejects the request before reading release evidence.

### Request Contract

The request body accepts only:

```json
{
  "release_id": "coding-fest-2026-clean",
  "run_id": "attackhostlightdos-20260607T132426Z-001"
}
```

Extra request fields are rejected. The client does not provide file paths, directories, ZIP paths, extraction targets, model choices, feature rows, or persistence options.

### Release Selection

The only allowlisted release is the canonical protected clean ZIP on the server:

```text
lab-telemetry/exports/dataset-releases/coding-fest-2026-xdr-dataset-training-batch-20260607T132426Z-clean.zip
```

Release lookup is by server-side `release_id`. Client-supplied paths are not accepted. In normal runtime configuration, the allowlisted path must resolve to the canonical clean ZIP path.

### ZIP Handling

The backend reads the ZIP directly. It does not extract, repair, rewrite, normalize on disk, or mutate the official release package.

The verifier inspects ZIP member safety, expected release prefixes, duplicate/ambiguous members, member size limits, total size limits, and read budget limits before returning evidence status. Required evidence is read from inside the archive.

### Response Contract

On success, the response returns sanitized verification and evidence inventory status only. It includes fields such as:

- `state`
- `verified`
- `release_id`
- `run_id`
- `batch_id`
- `scenario`
- `label`
- `sublabel`
- `completeness`
- `statuses`
- `feature_oracle`
- `inventory`
- `warnings`
- `rejection`

Inventory entries expose release-relative logical paths, byte sizes, SHA-256 hashes, evidence type, and status. The response must not expose server filesystem paths to the official ZIP.

On rejection, the response returns sanitized rejection state and a rejection code/message for the requested `release_id` and `run_id`.

### Phase 1A Exclusions

This endpoint does not perform:

- durable import or database persistence
- canonical event parsing
- 12-feature reconstruction from raw logs
- trained feature parity comparison
- ML-service calls
- model predictions
- prediction or explanation persistence
- incident creation
- graph construction
- SOC report generation
- frontend workflow updates
- live monitoring

The `feature_oracle` status in the response is verification-only. It confirms the expected official feature row exists and is internally consistent with run metadata; it is not treated as reconstructed runtime model input.

### Validation Commands

Use these backend validation commands for Phase 1A:

```powershell
python -m unittest discover -s backend\tests
python -m compileall backend\app
```
