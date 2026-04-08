from __future__ import annotations

from app.schemas import MLWindowRequest, NormalizedAlert


def build_window_request(events: list[NormalizedAlert]) -> MLWindowRequest:
    ordered = sorted(events, key=lambda item: item.event_timestamp)
    return MLWindowRequest(window=ordered)
