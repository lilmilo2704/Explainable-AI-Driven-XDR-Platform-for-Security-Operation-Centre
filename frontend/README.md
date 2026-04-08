# Explainable XDR/SIEM Frontend

User-facing SOC frontend for the Explainable XDR/SIEM prototype.

## Stack
- React + Vite + TypeScript
- React Router (multi-page SPA)
- React Query (data fetching/caching)
- Recharts (analytics charts)
- React Flow (causal graph visualization)
- Lucide React (icons)

## Routes
- `/dashboard`
- `/alerts`
- `/incidents`
- `/incidents/:id`
- `/assets`
- `/cases`
- `/coverage`
- `/models`

## Environment
Create `.env`:

```bash
VITE_API_BASE_URL=http://localhost:8000
```

If backend endpoints are missing, the UI automatically falls back to realistic mock data and remains fully demoable.

## Run
```bash
npm install
npm run dev
```

Open `http://localhost:5173`.

## Build
```bash
npm run build
npm run preview
```

## Docker
```bash
docker build -t xdr-frontend .
docker run --rm -p 5173:5173 xdr-frontend
```

## Product Scope Represented
The frontend includes complete demo flows for all six scenarios:
1. Credential Stuffing -> Account Takeover
2. Endpoint Compromise with Persistence
3. DDoS / Service Degradation
4. Insider Data Exfiltration
5. Web Attack / SQL Injection
6. Multi-Stage Attack

## Notes
- Backend `/api/alerts` and `/api/alerts/:id` are consumed directly when available.
- `/api/mock/seed` and `DELETE /api/alerts` are wired to dashboard quick actions.
- Other product views use route-aware mock fallback so judges can still see full platform capability in one frontend.
