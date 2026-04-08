from __future__ import annotations

from typing import Any

import httpx
from fastapi import HTTPException

from app.core.config import ML_SERVICE_URL
from app.schemas import MLEventRequest, MLPrediction, MLWindowAnalysis, MLWindowRequest


class MLClient:
    def __init__(self, base_url: str = ML_SERVICE_URL) -> None:
        self.base_url = base_url.rstrip("/")

    def predict_event(self, request: MLEventRequest) -> MLPrediction:
        payload = request.model_dump(mode="json")
        raw = self._post("/predict-event", payload)
        try:
            return MLPrediction.model_validate(raw)
        except Exception as exc:
            raise HTTPException(status_code=502, detail=f"Invalid ML event response: {exc}") from exc

    def analyze_window(self, request: MLWindowRequest) -> MLWindowAnalysis:
        payload = request.model_dump(mode="json")
        raw = self._post("/analyze-window", payload)
        try:
            return MLWindowAnalysis.model_validate(raw)
        except Exception as exc:
            raise HTTPException(status_code=502, detail=f"Invalid ML window response: {exc}") from exc

    def _post(self, path: str, json_payload: dict[str, Any]) -> dict[str, Any]:
        try:
            with httpx.Client(timeout=10.0) as client:
                response = client.post(f"{self.base_url}{path}", json=json_payload)
                response.raise_for_status()
                return response.json()
        except Exception as exc:
            raise HTTPException(status_code=502, detail=f"ML service error: {exc}") from exc
