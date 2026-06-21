from __future__ import annotations

import csv
import hashlib
import io
import json
import re
import zipfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any

from app.core.config import (
    CANONICAL_OFFICIAL_CLEAN_RELEASE_ZIP_PATH,
    OFFICIAL_CLEAN_RELEASE_ZIP_PATH,
)

OFFICIAL_RELEASE_ID = "coding-fest-2026-clean"
OFFICIAL_BATCH_ID = "training-batch-20260607T132426Z"
OFFICIAL_RELEASE_ROOT = "coding-fest-2026-xdr-dataset-training-batch-20260607T132426Z-clean"
INCOMPLETE_RUN_ID = "benign-20260607T132426Z-043"

RUN_ID_PATTERN = re.compile(r"^[a-z0-9]+-\d{8}T\d{6}Z-\d{3}$")
DRIVE_LETTER_PATTERN = re.compile(r"^[a-zA-Z]:")
CONTROL_CHAR_PATTERN = re.compile(r"[\x00-\x1f\x7f]")

ALLOWED_EXTENSIONS = {".csv", ".json", ".log", ".md"}
ALLOWED_RELEASE_PREFIXES = (
    "README.md",
    "batch-manifest/",
    "ml-features/",
    "model-ready/",
    "quality-summary/",
    "raw-evidence/",
    "windowed-dataset/",
)

REQUIRED_RUN_FILES = {
    "metadata": "metadata.json",
    "manifest": "manifest.json",
    "application": "webapp-slice.log",
    "nginx": "nginx-access-slice.log",
    "wazuh_summary": "wazuh-evidence-summary.json",
    "wazuh_alerts": "wazuh-alerts-slice.json",
    "wazuh_archives": "wazuh-archives-slice.json",
}
OPTIONAL_RUN_FILES = {"readme": "README.md"}
JSON_FILES_TO_PARSE = {"metadata", "manifest", "wazuh_summary", "wazuh_alerts", "wazuh_archives"}


@dataclass
class OfficialRunRejection(Exception):
    code: str
    message: str
    status_code: int = 400
    warnings: list[str] | None = None

    def as_response(self, release_id: str, run_id: str) -> dict[str, Any]:
        return {
            "state": "rejected",
            "verified": False,
            "release_id": release_id,
            "run_id": run_id,
            "rejection": {
                "code": self.code,
                "message": self.message,
            },
            "warnings": self.warnings or [],
        }


class ReadBudget:
    def __init__(self, max_bytes: int) -> None:
        self.max_bytes = max_bytes
        self.bytes_read = 0

    def charge(self, byte_count: int) -> None:
        self.bytes_read += byte_count
        if self.bytes_read > self.max_bytes:
            raise OfficialRunRejection(
                code="zip_read_budget_exceeded",
                message="Official release read budget was exceeded.",
                status_code=413,
            )


class OfficialRunVerifier:
    def __init__(
        self,
        release_zip_paths: dict[str, Path] | None = None,
        max_entry_bytes: int = 8 * 1024 * 1024,
        total_read_budget_bytes: int = 5 * 1024 * 1024,
        max_member_count: int = 10_000,
        max_total_uncompressed_bytes: int = 512 * 1024 * 1024,
    ) -> None:
        self.enforce_canonical_release_path = release_zip_paths is None
        self.release_zip_paths = release_zip_paths or {OFFICIAL_RELEASE_ID: OFFICIAL_CLEAN_RELEASE_ZIP_PATH}
        self.max_entry_bytes = max_entry_bytes
        self.total_read_budget_bytes = total_read_budget_bytes
        self.max_member_count = max_member_count
        self.max_total_uncompressed_bytes = max_total_uncompressed_bytes

    def verify(self, release_id: str, run_id: str) -> dict[str, Any]:
        validate_run_id(run_id)
        zip_path = self._release_path(release_id)
        budget = ReadBudget(self.total_read_budget_bytes)

        try:
            with zipfile.ZipFile(zip_path, mode="r") as archive:
                members = self._safe_members(archive)
                batch_manifest = self._read_json(
                    archive,
                    members,
                    f"{OFFICIAL_RELEASE_ROOT}/batch-manifest/batch-manifest.json",
                    budget,
                )
                manifest_entry = self._manifest_entry(batch_manifest, run_id)
                self._validate_manifest_entry(manifest_entry, run_id)

                feature_oracle = self._read_feature_oracle_row(archive, members, run_id, budget)
                raw_prefix = (
                    f"{OFFICIAL_RELEASE_ROOT}/raw-evidence/verified-runs/{run_id}/"
                )
                run_members = {
                    path: member for path, member in members.items() if path.startswith(raw_prefix)
                }
                if not run_members:
                    raise OfficialRunRejection(
                        code="raw_evidence_missing",
                        message="Raw verified evidence folder was not found for the requested run.",
                        status_code=404,
                    )

                inventory, parsed_json = self._verify_run_files(
                    archive, members, raw_prefix, budget
                )
                metadata = parsed_json.get("metadata", {})
                run_manifest = parsed_json.get("manifest", {})
                self._validate_run_consistency(
                    run_id,
                    manifest_entry,
                    feature_oracle,
                    metadata,
                    run_manifest,
                )
        except zipfile.BadZipFile as exc:
            raise OfficialRunRejection(
                code="corrupt_zip",
                message="Official release ZIP is corrupt or unreadable.",
                status_code=500,
            ) from exc
        except OSError as exc:
            raise OfficialRunRejection(
                code="zip_unavailable",
                message="Official release ZIP is unavailable.",
                status_code=500,
            ) from exc

        warnings = []
        if "readme" not in inventory:
            warnings.append("run_readme_missing")

        return {
            "state": "verified",
            "verified": True,
            "release_id": release_id,
            "run_id": run_id,
            "batch_id": batch_manifest.get("batch_id"),
            "scenario": metadata.get("scenario") or manifest_entry.get("scenario"),
            "label": metadata.get("main_label") or manifest_entry.get("label"),
            "sublabel": metadata.get("sublabel") or manifest_entry.get("sublabel"),
            "completeness": {
                "manifest_status": manifest_entry.get("status"),
                "verification_status": manifest_entry.get("verification_status"),
                "export_status": manifest_entry.get("export_status"),
                "metadata_verification_passed": metadata.get("verification_passed"),
                "training_suitability": bool(
                    metadata.get("clean_supervised_training_candidate")
                    or metadata.get("suitable_for_clean_supervised_training")
                    or feature_oracle.get("clean_supervised_training_candidate")
                ),
            },
            "statuses": {
                "batch_manifest": "present",
                "run_manifest": "present" if run_manifest else "missing",
                "metadata": "present" if metadata else "missing",
                "feature_oracle": "present",
                "application": inventory["application"]["status"],
                "nginx": inventory["nginx"]["status"],
                "wazuh_summary": inventory["wazuh_summary"]["status"],
                "wazuh_alerts": inventory["wazuh_alerts"]["status"],
                "wazuh_archives": inventory["wazuh_archives"]["status"],
            },
            "feature_oracle": {
                "status": "present",
                "usage": "verification_only",
                "clean_supervised_training_candidate": feature_oracle[
                    "clean_supervised_training_candidate"
                ],
            },
            "inventory": [inventory[key] for key in sorted(inventory)],
            "warnings": warnings,
            "rejection": None,
        }

    def _release_path(self, release_id: str) -> Path:
        if release_id != OFFICIAL_RELEASE_ID or release_id not in self.release_zip_paths:
            raise OfficialRunRejection(
                code="unknown_release",
                message="Release ID is not allowlisted.",
                status_code=404,
            )
        zip_path = self.release_zip_paths[release_id]
        if self.enforce_canonical_release_path and not same_resolved_path(
            zip_path, CANONICAL_OFFICIAL_CLEAN_RELEASE_ZIP_PATH
        ):
            raise OfficialRunRejection(
                code="release_path_not_canonical",
                message="Allowlisted release path does not resolve to the canonical clean ZIP.",
                status_code=500,
            )
        return zip_path

    def _safe_members(self, archive: zipfile.ZipFile) -> dict[str, zipfile.ZipInfo]:
        normalized_members: dict[str, zipfile.ZipInfo] = {}
        lowercase_members: dict[str, str] = {}
        members = archive.infolist()
        if len(members) > self.max_member_count:
            raise OfficialRunRejection(
                code="zip_member_count_exceeded",
                message="Official release contains too many ZIP members.",
                status_code=413,
            )
        total_uncompressed_bytes = 0
        for member in members:
            normalized = normalize_zip_member_name(member.filename)
            validate_zip_member_path(normalized)
            total_uncompressed_bytes += member.file_size
            if total_uncompressed_bytes > self.max_total_uncompressed_bytes:
                raise OfficialRunRejection(
                    code="zip_total_size_exceeded",
                    message="Official release declared uncompressed size exceeds the allowed limit.",
                    status_code=413,
                )
            if member.file_size > self.max_entry_bytes:
                raise OfficialRunRejection(
                    code="zip_entry_oversized",
                    message="Official release contains an entry over the allowed size.",
                    status_code=413,
                )
            if normalized in normalized_members:
                raise OfficialRunRejection(
                    code="duplicate_zip_member",
                    message="Official release contains duplicate normalized ZIP members.",
                    status_code=400,
                )
            lower = normalized.lower()
            if lower in lowercase_members:
                raise OfficialRunRejection(
                    code="duplicate_ambiguous_zip_member",
                    message="Official release contains ambiguous ZIP members after normalization.",
                    status_code=400,
                )
            lowercase_members[lower] = normalized
            normalized_members[normalized] = member
        return normalized_members

    def _manifest_entry(self, batch_manifest: dict[str, Any], run_id: str) -> dict[str, Any]:
        runs = batch_manifest.get("runs")
        if not isinstance(runs, list):
            raise OfficialRunRejection(
                code="batch_manifest_invalid",
                message="Batch manifest does not contain a valid runs list.",
                status_code=500,
            )
        for item in runs:
            if isinstance(item, dict) and item.get("run_id") == run_id:
                return item
        raise OfficialRunRejection(
            code="run_not_found",
            message="Requested run was not found in the batch manifest.",
            status_code=404,
        )

    def _validate_manifest_entry(self, entry: dict[str, Any], run_id: str) -> None:
        if run_id == INCOMPLETE_RUN_ID:
            raise OfficialRunRejection(
                code="run_incomplete",
                message="Requested run is the known incomplete official run.",
                status_code=422,
            )
        status = entry.get("status")
        verification_status = entry.get("verification_status")
        export_status = entry.get("export_status")
        if (
            status != "completed"
            or verification_status != "passed"
            or export_status != "exported"
        ):
            raise OfficialRunRejection(
                code="run_not_complete",
                message="Requested run did not complete verification and export.",
                status_code=422,
            )

    def _validate_run_consistency(
        self,
        run_id: str,
        manifest_entry: dict[str, Any],
        feature_oracle: dict[str, Any],
        metadata: dict[str, Any],
        run_manifest: dict[str, Any],
    ) -> None:
        for source_name, source in (("metadata", metadata), ("run_manifest", run_manifest)):
            source_run_id = source.get("run_id")
            if source_run_id is not None and source_run_id != run_id:
                raise OfficialRunRejection(
                    code=f"{source_name}_run_id_mismatch",
                    message=f"{source_name} run_id does not match the requested run.",
                    status_code=422,
                )

        manifest_scenario = manifest_entry.get("scenario")
        manifest_label = manifest_entry.get("label")
        manifest_sublabel = manifest_entry.get("sublabel")
        comparisons = [
            ("feature_oracle", "scenario", feature_oracle.get("scenario"), manifest_scenario),
            ("feature_oracle", "label", feature_oracle.get("label"), manifest_label),
            ("feature_oracle", "sublabel", feature_oracle.get("sublabel"), manifest_sublabel),
            ("metadata", "scenario", metadata.get("scenario"), manifest_scenario),
            ("metadata", "label", metadata.get("main_label") or metadata.get("label"), manifest_label),
            ("metadata", "sublabel", metadata.get("sublabel"), feature_oracle.get("sublabel")),
            ("run_manifest", "scenario", run_manifest.get("scenario"), manifest_scenario),
            (
                "run_manifest",
                "label",
                run_manifest.get("main_label") or run_manifest.get("label"),
                manifest_label,
            ),
            ("run_manifest", "sublabel", run_manifest.get("sublabel"), feature_oracle.get("sublabel")),
        ]
        for source_name, field_name, actual, expected in comparisons:
            if actual is not None and expected is not None and str(actual) != str(expected):
                raise OfficialRunRejection(
                    code=f"{source_name}_{field_name}_mismatch",
                    message=f"{source_name} {field_name} does not match official run metadata.",
                    status_code=422,
                )

    def _verify_run_files(
        self,
        archive: zipfile.ZipFile,
        members: dict[str, zipfile.ZipInfo],
        raw_prefix: str,
        budget: ReadBudget,
    ) -> tuple[dict[str, dict[str, Any]], dict[str, dict[str, Any]]]:
        inventory: dict[str, dict[str, Any]] = {}
        parsed_json: dict[str, dict[str, Any]] = {}
        expected_files = {**REQUIRED_RUN_FILES, **OPTIONAL_RUN_FILES}

        for evidence_type, filename in expected_files.items():
            logical_path = f"{raw_prefix}{filename}"
            member = members.get(logical_path)
            if member is None:
                if evidence_type in REQUIRED_RUN_FILES:
                    raise OfficialRunRejection(
                        code=f"{evidence_type}_missing",
                        message=f"Required {evidence_type} evidence is missing.",
                        status_code=422,
                    )
                continue
            digest = self._hash_member(archive, member, budget)
            inventory[evidence_type] = {
                "evidence_type": evidence_type,
                "logical_path": release_relative_path(logical_path),
                "byte_size": member.file_size,
                "sha256": digest,
                "status": "present",
            }
            if evidence_type in {"wazuh_alerts", "wazuh_archives"}:
                parsed_json[evidence_type] = self._read_json_lines_summary(
                    archive, members, logical_path, budget
                )
            elif evidence_type in JSON_FILES_TO_PARSE:
                parsed_json[evidence_type] = self._read_json(
                    archive,
                    members,
                    logical_path,
                    budget,
                )

        return inventory, parsed_json

    def _read_json(
        self,
        archive: zipfile.ZipFile,
        members: dict[str, zipfile.ZipInfo],
        normalized_path: str,
        budget: ReadBudget,
        require_object: bool = True,
    ) -> Any:
        member = members.get(normalized_path)
        if member is None:
            raise OfficialRunRejection(
                code="zip_member_missing",
                message="Required ZIP member is missing.",
                status_code=422,
            )
        data = self._read_member_bytes(archive, member, budget)
        try:
            raw = json.loads(data.decode("utf-8-sig"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise OfficialRunRejection(
                code="json_parse_failed",
                message="Required JSON evidence is not parseable.",
                status_code=422,
            ) from exc
        if require_object and not isinstance(raw, dict):
            raise OfficialRunRejection(
                code="json_shape_invalid",
                message="Required JSON evidence is not an object.",
                status_code=422,
            )
        return raw

    def _read_json_lines_summary(
        self,
        archive: zipfile.ZipFile,
        members: dict[str, zipfile.ZipInfo],
        normalized_path: str,
        budget: ReadBudget,
    ) -> dict[str, Any]:
        member = members.get(normalized_path)
        if member is None:
            raise OfficialRunRejection(
                code="zip_member_missing",
                message="Required ZIP member is missing.",
                status_code=422,
            )
        data = self._read_member_bytes(archive, member, budget)
        record_count = 0
        try:
            for line in data.decode("utf-8-sig").splitlines():
                if not line.strip():
                    continue
                json.loads(line)
                record_count += 1
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise OfficialRunRejection(
                code="json_parse_failed",
                message="Required JSON evidence is not parseable.",
                status_code=422,
            ) from exc
        return {"record_count": record_count}

    def _read_feature_oracle_row(
        self,
        archive: zipfile.ZipFile,
        members: dict[str, zipfile.ZipInfo],
        run_id: str,
        budget: ReadBudget,
    ) -> dict[str, Any]:
        csv_path = (
            f"{OFFICIAL_RELEASE_ROOT}/ml-features/"
            f"{OFFICIAL_BATCH_ID}-features.csv"
        )
        member = members.get(csv_path)
        if member is None:
            raise OfficialRunRejection(
                code="feature_oracle_missing",
                message="Feature oracle CSV is missing from the official release.",
                status_code=422,
            )
        budget.charge(member.file_size)
        with archive.open(member, "r") as raw_file:
            text_file = io.TextIOWrapper(raw_file, encoding="utf-8-sig", newline="")
            try:
                reader = csv.DictReader(text_file)
                matched_row: dict[str, str] | None = None
                for row in reader:
                    if row.get("run_id") == run_id:
                        if matched_row is not None:
                            raise OfficialRunRejection(
                                code="feature_oracle_duplicate_row",
                                message="Feature oracle CSV contains duplicate rows for the requested run.",
                                status_code=422,
                            )
                        matched_row = row
                if matched_row is not None:
                    candidate_value = (
                        matched_row.get("is_clean_supervised_training_candidate", "")
                        .strip()
                        .lower()
                    )
                    return {
                        "present": True,
                        "scenario": empty_to_none(matched_row.get("scenario")),
                        "label": empty_to_none(
                            matched_row.get("main_label") or matched_row.get("label")
                        ),
                        "sublabel": empty_to_none(matched_row.get("sublabel")),
                        "clean_supervised_training_candidate": candidate_value == "true",
                    }
            except csv.Error as exc:
                raise OfficialRunRejection(
                    code="feature_oracle_parse_failed",
                    message="Feature oracle CSV is not parseable.",
                    status_code=422,
                ) from exc
        raise OfficialRunRejection(
            code="feature_oracle_row_missing",
            message="Feature oracle row was not found for the requested run.",
            status_code=422,
        )

    def _hash_member(
        self,
        archive: zipfile.ZipFile,
        member: zipfile.ZipInfo,
        budget: ReadBudget,
    ) -> str:
        digest = hashlib.sha256()
        with archive.open(member, "r") as raw_file:
            while True:
                chunk = raw_file.read(64 * 1024)
                if not chunk:
                    break
                budget.charge(len(chunk))
                digest.update(chunk)
        return digest.hexdigest()

    def _read_member_bytes(
        self,
        archive: zipfile.ZipFile,
        member: zipfile.ZipInfo,
        budget: ReadBudget,
    ) -> bytes:
        with archive.open(member, "r") as raw_file:
            data = raw_file.read()
        budget.charge(len(data))
        return data


def validate_run_id(run_id: str) -> None:
    if (
        not run_id
        or len(run_id) > 128
        or CONTROL_CHAR_PATTERN.search(run_id)
        or "/" in run_id
        or "\\" in run_id
        or ":" in run_id
        or "." in run_id
        or DRIVE_LETTER_PATTERN.match(run_id)
        or not RUN_ID_PATTERN.match(run_id)
    ):
        raise OfficialRunRejection(
            code="invalid_run_id",
            message="Run ID is not a valid official logical run ID.",
            status_code=422,
        )


def normalize_zip_member_name(name: str) -> str:
    return name.replace("\\", "/")


def validate_zip_member_path(path: str) -> None:
    if (
        not path
        or CONTROL_CHAR_PATTERN.search(path)
        or path.startswith("/")
        or path.startswith("\\")
        or DRIVE_LETTER_PATTERN.match(path)
    ):
        raise OfficialRunRejection(
            code="unsafe_zip_member",
            message="Official release contains an unsafe ZIP member path.",
            status_code=400,
        )
    parts = path.split("/")
    is_directory = path.endswith("/")
    path_parts = parts[:-1] if is_directory else parts
    if any(part in {"", ".", ".."} for part in path_parts):
        raise OfficialRunRejection(
            code="unsafe_zip_member",
            message="Official release contains an unsafe ZIP member path.",
            status_code=400,
        )
    if not is_directory and PurePosixPath(path).suffix.lower() not in ALLOWED_EXTENSIONS:
        raise OfficialRunRejection(
            code="unsupported_zip_member",
            message="Official release contains an unsupported ZIP member type.",
            status_code=400,
        )
    root_prefix = f"{OFFICIAL_RELEASE_ROOT}/"
    if path != OFFICIAL_RELEASE_ROOT and not path.startswith(root_prefix):
        raise OfficialRunRejection(
            code="unexpected_zip_prefix",
            message="Official release contains a member outside the expected release root.",
            status_code=400,
        )
    if path == OFFICIAL_RELEASE_ROOT or path == root_prefix:
        return
    release_relative = path.removeprefix(root_prefix)
    if not any(
        release_relative == prefix or release_relative.startswith(prefix)
        for prefix in ALLOWED_RELEASE_PREFIXES
    ):
        raise OfficialRunRejection(
            code="unexpected_zip_prefix",
            message="Official release contains a member outside allowed release prefixes.",
            status_code=400,
        )


def release_relative_path(path: str) -> str:
    return path.removeprefix(f"{OFFICIAL_RELEASE_ROOT}/")


def same_resolved_path(left: Path, right: Path) -> bool:
    return left.resolve(strict=False) == right.resolve(strict=False)


def empty_to_none(value: Any) -> Any:
    if isinstance(value, str) and value == "":
        return None
    return value


official_run_import_service = OfficialRunVerifier()
