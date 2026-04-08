# Explainable XDR/SIEM Prototype (Layered Skeleton)

This repository now follows a layered, backend-orchestrated architecture:

`Wazuh-style telemetry -> Backend normalization/preprocessing -> ML intelligence service -> Backend persistence/API -> Frontend`

## Service Topology

- `frontend` (React/Vite analyst UI): `http://localhost:5173`
- `backend` (FastAPI orchestration): `http://localhost:8000`
- `ml-service` (FastAPI intelligence contract, mock implementation): `http://localhost:5000`
- `db` (PostgreSQL): `localhost:5432`

## Run

```bash
docker compose up --build
```

## Key Contracts

### Backend APIs

- `GET /health`
- `POST /api/alerts/ingest`
- `POST /api/incidents/ingest-window`
- `GET /api/alerts`
- `GET /api/alerts/{id}`
- `GET /api/incidents`
- `GET /api/incidents/{id}`
- `GET /api/dashboard/summary`
- `GET /api/models`
- `GET /api/assets`
- `GET /api/cases`
- `POST /api/mock/seed`
- `DELETE /api/reset`
- `DELETE /api/alerts` (compat alias)

### ML Service APIs

- `POST /predict-event`
- `POST /analyze-window`

Legacy aliases retained for compatibility:
- `POST /classify-alert`
- `POST /classify-window`

## Current Stage Behavior

The ML service is mock/placeholder logic today, but the response contracts already include:

- incident classification (`incident_type`, `confidence`, `severity`)
- analyst response guidance
- explanation summary
- correlated events
- timeline events
- causal graph
- narrative summary text

This allows real model replacement later without breaking backend/frontend integration.

## Seed + Verify Flow

1. Seed mock telemetry:

```bash
curl -X POST http://localhost:8000/api/mock/seed
```

2. Verify backend-persisted alerts/incidents:

```bash
curl http://localhost:8000/api/alerts
curl http://localhost:8000/api/incidents
```

3. Open frontend:

- `http://localhost:5173/dashboard`
- inspect `/incidents` and `/incidents/:id` for timeline/graph/evidence from backend APIs.
