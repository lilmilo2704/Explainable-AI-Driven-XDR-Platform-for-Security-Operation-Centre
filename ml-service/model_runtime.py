from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from io import StringIO
from pathlib import Path
from typing import Any

import joblib
import numpy as np
import pandas as pd
from fastapi import HTTPException


APP_DIR = Path(__file__).resolve().parent
MODELS_DIR = APP_DIR / "models"
TEACHER_DIR = MODELS_DIR / "teachers"
SURROGATE_DIR = MODELS_DIR / "surrogates"
METADATA_DIR = MODELS_DIR / "metadata"

MODEL_VERSION = "xdr-run-level-dos-ebm-surrogate-v1"
TARGET = "main_label"
POSITIVE_CLASS = "DoS_DDoS"

BASE_FEATURES = [
    "request_completed_count",
    "request_rate_per_second",
    "peak_request_rate_per_second",
    "unique_path_count",
    "repeated_path_count",
    "search_query_count",
    "avg_response_time_ms",
    "max_response_time_ms",
    "p95_response_time_ms",
    "health_check_count",
    "avg_health_check_latency_ms",
    "max_health_check_latency_ms",
]

ENGINEERED_FEATURES = [
    "request_repeat_ratio",
    "search_request_ratio",
    "health_check_ratio",
    "latency_spread_ms",
    "p95_avg_latency_ratio",
]

FINAL_FEATURES = BASE_FEATURES + ENGINEERED_FEATURES

MODEL_CONFIGS = {
    "ebm": {
        "display_name": "Explainable Boosting Machine",
        "teacher_path": TEACHER_DIR / "ebm_best_model.joblib",
        "surrogate_path": TEACHER_DIR / "ebm_best_model.joblib",
        "plot_path": "/model-explanations/ebm/original_ebm_global_feature_importance.png",
        "surrogate_note": "Native EBM explanations; teacher and explainer are the same model.",
    },
    "xgboost": {
        "display_name": "XGBoost",
        "teacher_path": TEACHER_DIR / "xgboost_best_model.joblib",
        "surrogate_path": SURROGATE_DIR / "ebm_surrogate_for_xgboost.joblib",
        "plot_path": "/model-explanations/surrogates/xgboost/ebm_surrogate_xgboost_global_feature_importance.png",
        "surrogate_note": "EBM surrogate trained from XGBoost pseudo-labels.",
    },
    "random_forest": {
        "display_name": "Random Forest",
        "teacher_path": TEACHER_DIR / "random_forest_best_model.joblib",
        "surrogate_path": SURROGATE_DIR / "ebm_surrogate_for_random_forest.joblib",
        "plot_path": "/model-explanations/surrogates/random_forest/ebm_surrogate_random_forest_global_feature_importance.png",
        "surrogate_note": "EBM surrogate trained from Random Forest pseudo-labels.",
    },
    "svm": {
        "display_name": "SVM",
        "teacher_path": TEACHER_DIR / "svm_best_model.joblib",
        "surrogate_path": SURROGATE_DIR / "ebm_surrogate_for_svm.joblib",
        "plot_path": "/model-explanations/surrogates/svm/ebm_surrogate_svm_global_feature_importance.png",
        "surrogate_note": "EBM surrogate trained from SVM pseudo-labels.",
    },
    "mlp": {
        "display_name": "MLP",
        "teacher_path": TEACHER_DIR / "mlp_best_model.joblib",
        "surrogate_path": SURROGATE_DIR / "ebm_surrogate_for_mlp.joblib",
        "plot_path": "/model-explanations/surrogates/mlp/ebm_surrogate_mlp_global_feature_importance.png",
        "surrogate_note": "EBM surrogate trained from MLP pseudo-labels.",
    },
}


def _load_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def _load_target_encoder() -> Any | None:
    path = METADATA_DIR / "target_label_encoder.joblib"
    return joblib.load(path) if path.exists() else None


def _load_bundle(name: str, config: dict[str, Any]) -> dict[str, Any] | None:
    if not config["teacher_path"].exists() or not config["surrogate_path"].exists():
        return None
    return {
        **config,
        "name": name,
        "teacher_model": joblib.load(config["teacher_path"]),
        "surrogate_model": joblib.load(config["surrogate_path"]),
    }


RUN_SUMMARY = _load_json(METADATA_DIR / "run_summary.json")
SURROGATE_REPORT = _load_json(METADATA_DIR / "surrogate_fidelity_error_report.json")
TARGET_ENCODER = _load_target_encoder()
MODEL_BUNDLES = {
    name: bundle
    for name, config in MODEL_CONFIGS.items()
    if (bundle := _load_bundle(name, config)) is not None
}


def models_available() -> bool:
    return bool(MODEL_BUNDLES)


def model_status() -> dict[str, Any]:
    return {
        "loaded": sorted(MODEL_BUNDLES.keys()),
        "missing": [name for name in MODEL_CONFIGS if name not in MODEL_BUNDLES],
        "required_base_features": BASE_FEATURES,
        "engineered_features": ENGINEERED_FEATURES,
        "target": TARGET,
        "target_classes": RUN_SUMMARY.get("target_classes", ["Benign", POSITIVE_CLASS]),
        "model_version": MODEL_VERSION,
    }


def safe_divide(numerator: pd.Series, denominator: pd.Series) -> pd.Series:
    denominator = denominator.replace(0, np.nan)
    return (numerator / denominator).replace([np.inf, -np.inf], np.nan).fillna(0)


def normalize_rows(payload: Any) -> pd.DataFrame:
    rows = payload.get("rows", payload) if isinstance(payload, dict) else payload
    if isinstance(rows, dict):
        rows = [rows]
    if not isinstance(rows, list) or not rows or not all(isinstance(row, dict) for row in rows):
        raise HTTPException(status_code=422, detail="Body must be a row object, a list of rows, or {'rows': [...]} .")
    return pd.DataFrame(rows)


def read_csv_rows(csv_text: str) -> pd.DataFrame:
    try:
        raw_df = pd.read_csv(StringIO(csv_text))
    except Exception as exc:
        raise HTTPException(status_code=422, detail=f"Could not parse CSV body: {exc}") from exc
    if raw_df.empty:
        raise HTTPException(status_code=422, detail="CSV body did not contain any rows.")
    return raw_df


def prepare_features(raw_df: pd.DataFrame) -> pd.DataFrame:
    missing = [col for col in BASE_FEATURES if col not in raw_df.columns]
    if missing:
        raise HTTPException(
            status_code=422,
            detail={
                "message": "Missing required raw feature columns.",
                "missing_columns": missing,
                "required_base_features": BASE_FEATURES,
            },
        )

    X = raw_df[BASE_FEATURES].copy()
    for col in BASE_FEATURES:
        X[col] = pd.to_numeric(X[col], errors="coerce")

    bad_columns = [col for col in BASE_FEATURES if X[col].isna().any()]
    if bad_columns:
        raise HTTPException(
            status_code=422,
            detail={"message": "Required feature columns must be numeric and non-empty.", "invalid_columns": bad_columns},
        )

    X["request_repeat_ratio"] = safe_divide(X["repeated_path_count"], X["request_completed_count"])
    X["search_request_ratio"] = safe_divide(X["search_query_count"], X["request_completed_count"])
    X["health_check_ratio"] = safe_divide(X["health_check_count"], X["request_completed_count"])
    X["latency_spread_ms"] = X["max_response_time_ms"] - X["avg_response_time_ms"]
    X["p95_avg_latency_ratio"] = safe_divide(X["p95_response_time_ms"], X["avg_response_time_ms"])
    return X[FINAL_FEATURES]


def class_name(label: int) -> str:
    if TARGET_ENCODER is not None:
        return str(TARGET_ENCODER.inverse_transform([int(label)])[0])
    return POSITIVE_CLASS if int(label) == 1 else "Benign"


def class_id(label_name: str) -> int:
    if TARGET_ENCODER is not None:
        return int(TARGET_ENCODER.transform([label_name])[0])
    return 1 if label_name == POSITIVE_CLASS else 0


def get_model_bundle(model_name: str) -> dict[str, Any]:
    normalized = model_name.lower()
    if normalized not in MODEL_BUNDLES:
        raise HTTPException(
            status_code=404,
            detail={"message": f"Unknown model '{model_name}'.", "available_models": sorted(MODEL_BUNDLES.keys())},
        )
    return MODEL_BUNDLES[normalized]


def global_importance(surrogate_model: Any, top_n: int | None = 10) -> list[dict[str, Any]]:
    exp = surrogate_model.explain_global()
    data = exp.data()
    rows = [
        {"feature": str(name), "importance": float(score)}
        for name, score in zip(data["names"], data["scores"])
    ]
    rows.sort(key=lambda item: abs(item["importance"]), reverse=True)
    return rows[:top_n] if top_n else rows


def local_importance(
    surrogate_model: Any,
    X: pd.DataFrame,
    surrogate_predictions: np.ndarray,
    top_n: int | None = 10,
) -> list[list[dict[str, Any]]]:
    exp = surrogate_model.explain_local(X, surrogate_predictions)
    all_rows = []
    for idx in range(len(X)):
        data = exp.data(idx)
        rows = [
            {
                "feature": str(name),
                "value": None if pd.isna(value) else float(value),
                "contribution": float(score),
                "abs_contribution": float(abs(score)),
                "direction": "up" if float(score) >= 0 else "down",
            }
            for name, value, score in zip(data["names"], data["values"], data["scores"])
        ]
        rows.sort(key=lambda item: item["abs_contribution"], reverse=True)
        all_rows.append(rows[:top_n] if top_n else rows)
    return all_rows


def predict_proba_map(model: Any, X: pd.DataFrame, row_index: int, pred: int) -> dict[str, float]:
    if hasattr(model, "predict_proba"):
        probabilities = model.predict_proba(X)
        return {
            class_name(class_idx): float(probabilities[row_index, class_idx])
            for class_idx in range(probabilities.shape[1])
        }
    return {class_name(0): float(pred == 0), class_name(1): float(pred == 1)}


def predict_dataframe(raw_df: pd.DataFrame, model_name: str = "ebm", top_n: int | None = 10) -> dict[str, Any]:
    bundle = get_model_bundle(model_name)
    X = prepare_features(raw_df)
    teacher_model = bundle["teacher_model"]
    surrogate_model = bundle["surrogate_model"]
    teacher_preds = teacher_model.predict(X).astype(int)
    surrogate_preds = surrogate_model.predict(X).astype(int)
    local_rows = local_importance(surrogate_model, X, surrogate_preds, top_n=top_n)

    predictions = []
    for idx, pred in enumerate(teacher_preds):
        proba_map = predict_proba_map(teacher_model, X, idx, int(pred))
        local_features = local_rows[idx]
        predictions.append(
            {
                "row_index": int(idx),
                "teacher_predicted_label": class_name(int(pred)),
                "teacher_predicted_class_id": int(pred),
                "teacher_probabilities": proba_map,
                "surrogate_predicted_label": class_name(int(surrogate_preds[idx])),
                "surrogate_predicted_class_id": int(surrogate_preds[idx]),
                "teacher_surrogate_match": bool(int(pred) == int(surrogate_preds[idx])),
                "processed_features": {col: float(X.iloc[idx][col]) for col in X.columns},
                "surrogate_local_feature_importance": local_features,
                "explanation_features": [
                    {
                        "feature": item["feature"],
                        "contribution": item["contribution"],
                        "direction": item["direction"],
                        "value": item["value"],
                    }
                    for item in local_features
                ],
            }
        )

    return {
        "model_name": model_name.lower(),
        "teacher_model": bundle["display_name"],
        "teacher_model_path": str(bundle["teacher_path"].relative_to(APP_DIR)),
        "explanation_model": "Explainable Boosting Machine surrogate",
        "surrogate_model_path": str(bundle["surrogate_path"].relative_to(APP_DIR)),
        "surrogate_note": bundle["surrogate_note"],
        "row_count": int(len(raw_df)),
        "target": TARGET,
        "dropped_or_ignored_columns": [col for col in raw_df.columns if col not in BASE_FEATURES],
        "required_base_features": BASE_FEATURES,
        "engineered_features": ENGINEERED_FEATURES,
        "surrogate_global_feature_importance": global_importance(surrogate_model, top_n=top_n),
        "predictions": predictions,
    }


def _to_number(value: Any) -> float | None:
    if value is None or value == "":
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _parse_timestamp(value: Any) -> datetime | None:
    if isinstance(value, datetime):
        return value
    if not value:
        return None
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None


def _extract_paths(text: str) -> list[str]:
    request_paths = re.findall(r"\b(?:GET|POST|PUT|PATCH|DELETE)\s+(/[^\s\"']+)", text, flags=re.IGNORECASE)
    if request_paths:
        return request_paths
    fallback = re.findall(r"(/[A-Za-z0-9._~:/?#\[\]@!$&'()*+,;=%-]+)", text)
    return fallback


def _extract_response_time(event: dict[str, Any]) -> float | None:
    features = event.get("features") or {}
    for key in (
        "response_time_ms",
        "request_duration_ms",
        "duration_ms",
        "avg_response_time_ms",
        "max_response_time_ms",
    ):
        number = _to_number(features.get(key))
        if number is not None:
            return number

    text = f"{event.get('full_log', '')} {features.get('rule_description', '')}"
    for pattern in (r"(?:response|latency|duration)[_=:\s]+(\d+(?:\.\d+)?)\s*ms", r"(\d+(?:\.\d+)?)\s*ms"):
        match = re.search(pattern, text, flags=re.IGNORECASE)
        if match:
            return float(match.group(1))
    return None


def _event_text(event: dict[str, Any]) -> str:
    features = event.get("features") or {}
    return " ".join(
        str(value)
        for value in (
            features.get("rule_description", ""),
            event.get("full_log", ""),
            event.get("scenario_type", ""),
            event.get("event_family", ""),
        )
    ).lower()


def is_dos_candidate(events: list[dict[str, Any]]) -> bool:
    keywords = ("dos", "ddos", "flood", "high traffic", "too many requests", "connection spike", "rate limit")
    return any(any(keyword in _event_text(event) for keyword in keywords) for event in events)


def events_to_raw_row(events: list[dict[str, Any]]) -> tuple[dict[str, float], str]:
    if not events:
        raise HTTPException(status_code=422, detail="Event window cannot be empty.")

    first_features = events[0].get("features") or {}
    if all(feature in first_features for feature in BASE_FEATURES):
        return {feature: float(first_features[feature]) for feature in BASE_FEATURES}, "provided_run_features"

    texts = [_event_text(event) for event in events]
    paths = []
    response_times = []
    health_latencies = []
    timestamps = []
    search_count = 0
    health_count = 0

    for event, text in zip(events, texts):
        paths.extend(_extract_paths(text))
        response_time = _extract_response_time(event)
        if response_time is not None:
            response_times.append(response_time)
        if "search" in text or "query" in text:
            search_count += 1
        if "health" in text:
            health_count += 1
            if response_time is not None:
                health_latencies.append(response_time)
        timestamp = _parse_timestamp(event.get("event_timestamp"))
        if timestamp is not None:
            timestamps.append(timestamp)

    request_count = max(len(events), 1)
    if len(timestamps) >= 2:
        duration = max((max(timestamps) - min(timestamps)).total_seconds(), 1.0)
    else:
        duration = max(float(request_count), 1.0)

    unique_path_count = len(set(paths)) if paths else max(1, min(request_count, 2))
    repeated_path_count = max(request_count - unique_path_count, 0)
    if response_times:
        avg_response = float(np.mean(response_times))
        max_response = float(np.max(response_times))
        p95_response = float(np.percentile(response_times, 95))
    else:
        suspicious = is_dos_candidate(events)
        avg_response = 350.0 if suspicious else 120.0
        max_response = 900.0 if suspicious else 220.0
        p95_response = 800.0 if suspicious else 200.0

    if health_latencies:
        avg_health = float(np.mean(health_latencies))
        max_health = float(np.max(health_latencies))
    else:
        avg_health = avg_response if health_count else 0.0
        max_health = max_response if health_count else 0.0

    request_rate = request_count / duration
    row = {
        "request_completed_count": float(request_count),
        "request_rate_per_second": float(request_rate),
        "peak_request_rate_per_second": float(max(request_rate, request_count if duration <= request_count else request_rate)),
        "unique_path_count": float(unique_path_count),
        "repeated_path_count": float(repeated_path_count),
        "search_query_count": float(search_count),
        "avg_response_time_ms": avg_response,
        "max_response_time_ms": max_response,
        "p95_response_time_ms": p95_response,
        "health_check_count": float(health_count),
        "avg_health_check_latency_ms": avg_health,
        "max_health_check_latency_ms": max_health,
    }
    return row, "estimated_from_normalized_events"


def prediction_to_xdr_response(
    prediction: dict[str, Any],
    model_name: str,
    feature_source: str,
    correlated_events: list[str] | None = None,
    timeline_events: list[dict[str, Any]] | None = None,
    causal_graph: dict[str, Any] | None = None,
) -> dict[str, Any]:
    label = prediction["teacher_predicted_label"]
    probabilities = prediction["teacher_probabilities"]
    confidence = float(probabilities.get(label, max(probabilities.values()) if probabilities else 0.5))
    dos_probability = float(probabilities.get(POSITIVE_CLASS, confidence if label == POSITIVE_CLASS else 1.0 - confidence))
    is_attack = label == POSITIVE_CLASS
    severity = "high" if is_attack and dos_probability >= 0.8 else "medium" if is_attack else "low"
    incident_type = "DDoS" if is_attack else "Unknown"
    recommended = (
        "Enable rate limiting, validate edge filtering, and inspect service saturation telemetry."
        if is_attack
        else "Continue collecting telemetry; the run-level detector scored this window as benign."
    )
    top_features = prediction["explanation_features"][:5]
    feature_names = ", ".join(item["feature"] for item in top_features)
    summary = (
        f"{MODEL_CONFIGS[model_name]['display_name']} predicted {label} with {confidence:.2f} confidence. "
        f"Top EBM explanation drivers: {feature_names}. Feature source: {feature_source}."
    )
    response = {
        "incident_type": incident_type,
        "confidence": confidence,
        "severity": severity,
        "recommended_action": recommended,
        "model_version": f"{MODEL_VERSION}:{model_name}",
        "explanation_summary": summary,
        "explanation_features": top_features,
        "class_probabilities": [
            {"class_name": class_label, "value": score}
            for class_label, score in sorted(probabilities.items())
        ],
        "raw_model_label": label,
        "feature_source": feature_source,
    }
    if correlated_events is not None:
        response.update(
            {
                "correlated_events": correlated_events,
                "timeline_events": timeline_events or [],
                "causal_graph": causal_graph or {"nodes": [], "edges": []},
                "summary_text": (
                    f"Run-level DDoS detector analyzed {len(correlated_events)} normalized events "
                    f"and returned {label} at {round(confidence * 100)}% confidence."
                ),
            }
        )
    return response


def predict_events(events: list[dict[str, Any]], model_name: str = "ebm") -> dict[str, Any]:
    row, feature_source = events_to_raw_row(events)
    result = predict_dataframe(pd.DataFrame([row]), model_name=model_name, top_n=10)
    return prediction_to_xdr_response(result["predictions"][0], model_name, feature_source)


def analyze_events(events: list[dict[str, Any]], model_name: str = "ebm") -> dict[str, Any]:
    row, feature_source = events_to_raw_row(events)
    result = predict_dataframe(pd.DataFrame([row]), model_name=model_name, top_n=10)

    event_results = result["predictions"][0]
    correlated = [str(event.get("external_rule_id", f"event-{idx}")) for idx, event in enumerate(events, start=1)]
    timeline_events = []
    for index, event in enumerate(events, start=1):
        timestamp = _parse_timestamp(event.get("event_timestamp")) or datetime.now(timezone.utc)
        timeline_events.append(
            {
                "id": f"t-{index}",
                "timestamp": timestamp.astimezone(timezone.utc).isoformat(),
                "event_type": "DDoS telemetry" if is_dos_candidate([event]) else "Observation",
                "asset": event.get("agent_name"),
                "ip": event.get("source_ip"),
                "raw_log": event.get("full_log", ""),
                "explanation": "Included in the run-level feature estimate used by the trained detector.",
            }
        )

    confidence = max(event_results["teacher_probabilities"].values())
    nodes = [
        {
            "id": f"n-{idx}",
            "position": {"x": 80 + (idx * 220), "y": 120},
            "data": {
                "label": event.get("agent_name", f"event-{idx + 1}"),
                "category": "service",
                "confidence": float(confidence),
            },
        }
        for idx, event in enumerate(events)
    ]
    edges = [
        {
            "id": f"e-{idx}",
            "source": nodes[idx - 1]["id"],
            "target": nodes[idx]["id"],
            "label": "same run-level window",
            "data": {"confidence": float(confidence), "explanation": "Events contributed to the same detector feature vector."},
        }
        for idx in range(1, len(nodes))
    ]
    return prediction_to_xdr_response(
        event_results,
        model_name,
        feature_source,
        correlated_events=correlated,
        timeline_events=timeline_events,
        causal_graph={"nodes": nodes, "edges": edges},
    )
