from __future__ import annotations

import os
from pathlib import Path

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql+psycopg2://xdr:xdrpass@db:5432/xdrdb")
ML_SERVICE_URL = os.getenv("ML_SERVICE_URL", "http://ml-service:5000")
SEED_ALERTS_PATH = Path(os.getenv("SEED_ALERTS_PATH", "/app/samples/seed_alerts.json"))
SEED_MULTI_STAGE_PATH = Path(os.getenv("SEED_MULTI_STAGE_PATH", "/app/samples/multi_stage_window.json"))
