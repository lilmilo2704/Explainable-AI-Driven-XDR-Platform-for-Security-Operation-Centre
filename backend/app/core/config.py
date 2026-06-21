from __future__ import annotations

import os
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql+psycopg2://xdr:xdrpass@db:5432/xdrdb")
ML_SERVICE_URL = os.getenv("ML_SERVICE_URL", "http://ml-service:5000")
SEED_ALERTS_PATH = Path(os.getenv("SEED_ALERTS_PATH", "/app/samples/seed_alerts.json"))
SEED_MULTI_STAGE_PATH = Path(os.getenv("SEED_MULTI_STAGE_PATH", "/app/samples/multi_stage_window.json"))

CANONICAL_OFFICIAL_CLEAN_RELEASE_ZIP_PATH = (
    REPO_ROOT
    / "lab-telemetry"
    / "exports"
    / "dataset-releases"
    / "coding-fest-2026-xdr-dataset-training-batch-20260607T132426Z-clean.zip"
)
OFFICIAL_CLEAN_RELEASE_ZIP_PATH = CANONICAL_OFFICIAL_CLEAN_RELEASE_ZIP_PATH
XDR_DEMO_IMPORT_ENABLED = os.getenv("XDR_DEMO_IMPORT_ENABLED", "false").lower() == "true"
XDR_DEMO_API_TOKEN = os.getenv("XDR_DEMO_API_TOKEN", "")
