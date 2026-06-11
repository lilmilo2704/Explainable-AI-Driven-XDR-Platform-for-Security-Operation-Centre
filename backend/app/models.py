from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from sqlalchemy import DateTime, Float, ForeignKey, Integer, String, Text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


class Base(DeclarativeBase):
    pass


class Alert(Base):
    __tablename__ = "alerts"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    rule_id: Mapped[str] = mapped_column(String(128), index=True)
    rule_level: Mapped[int] = mapped_column(Integer)
    rule_description: Mapped[str] = mapped_column(Text)
    agent_id: Mapped[str] = mapped_column(String(128), index=True)
    agent_name: Mapped[str] = mapped_column(String(256), index=True)
    source_ip: Mapped[str | None] = mapped_column(String(64), nullable=True)
    full_log: Mapped[str] = mapped_column(Text)
    raw_payload: Mapped[dict[str, Any]] = mapped_column(JSONB)
    normalized_payload: Mapped[dict[str, Any]] = mapped_column(JSONB)
    event_timestamp: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    scenario_type: Mapped[str | None] = mapped_column(String(128), nullable=True, index=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )

    prediction: Mapped["Prediction | None"] = relationship(
        back_populates="alert", cascade="all, delete-orphan", uselist=False
    )
    incident_links: Mapped[list["IncidentAlertLink"]] = relationship(
        back_populates="alert", cascade="all, delete-orphan"
    )


class Prediction(Base):
    __tablename__ = "predictions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    alert_id: Mapped[int] = mapped_column(ForeignKey("alerts.id", ondelete="CASCADE"), index=True)
    incident_id: Mapped[int | None] = mapped_column(
        ForeignKey("incidents.id", ondelete="SET NULL"), nullable=True, index=True
    )
    incident_type: Mapped[str] = mapped_column(String(128), index=True)
    confidence: Mapped[float] = mapped_column(Float)
    severity: Mapped[str] = mapped_column(String(32), index=True)
    recommended_action: Mapped[str] = mapped_column(Text)
    model_version: Mapped[str] = mapped_column(String(64))
    explanation_summary: Mapped[str] = mapped_column(Text)
    explanation_features: Mapped[list[dict[str, Any]]] = mapped_column(JSONB, default=list)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )

    alert: Mapped[Alert] = relationship(back_populates="prediction")
    incident: Mapped["Incident | None"] = relationship(back_populates="predictions")


class Incident(Base):
    __tablename__ = "incidents"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    incident_type: Mapped[str] = mapped_column(String(128), index=True)
    confidence: Mapped[float] = mapped_column(Float)
    severity: Mapped[str] = mapped_column(String(32), index=True)
    recommended_action: Mapped[str] = mapped_column(Text)
    model_version: Mapped[str] = mapped_column(String(64))
    explanation_summary: Mapped[str] = mapped_column(Text)
    explanation_features: Mapped[list[dict[str, Any]]] = mapped_column(JSONB, default=list)
    summary_text: Mapped[str] = mapped_column(Text, default="")
    timeline_events: Mapped[list[dict[str, Any]]] = mapped_column(JSONB, default=list)
    causal_graph: Mapped[dict[str, Any]] = mapped_column(JSONB, default=dict)
    correlated_event_ids: Mapped[list[int]] = mapped_column(JSONB, default=list)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )

    alert_links: Mapped[list["IncidentAlertLink"]] = relationship(
        back_populates="incident", cascade="all, delete-orphan"
    )
    predictions: Mapped[list[Prediction]] = relationship(back_populates="incident")


class IncidentAlertLink(Base):
    __tablename__ = "incident_alert_links"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    incident_id: Mapped[int] = mapped_column(ForeignKey("incidents.id", ondelete="CASCADE"), index=True)
    alert_id: Mapped[int] = mapped_column(ForeignKey("alerts.id", ondelete="CASCADE"), index=True)

    incident: Mapped[Incident] = relationship(back_populates="alert_links")
    alert: Mapped[Alert] = relationship(back_populates="incident_links")
