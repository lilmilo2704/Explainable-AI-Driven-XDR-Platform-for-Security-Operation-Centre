from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
import warnings
import zipfile
from importlib import reload
from pathlib import Path
from unittest.mock import patch

from fastapi.testclient import TestClient

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

os.environ.setdefault("DATABASE_URL", "sqlite+pysqlite:///:memory:")

from app import main
from app.core import config as core_config  # noqa: E402
from app.services.official_run_import_service import (  # noqa: E402
    INCOMPLETE_RUN_ID,
    OFFICIAL_RELEASE_ID,
    OFFICIAL_RELEASE_ROOT,
    OfficialRunRejection,
    OfficialRunVerifier,
    official_run_import_service,
)

RUN_ID = "attackerhostlightdos-20260607T132426Z-201"
OTHER_RUN_ID = "attackerhostlightdos-20260607T132426Z-202"


def create_fixture_zip(
    zip_path: Path,
    *,
    run_id: str = RUN_ID,
    manifest_run_id: str | None = RUN_ID,
    manifest_status: str = "completed",
    verification_status: str = "passed",
    export_status: str = "exported",
    feature_row_run_id: str | None = RUN_ID,
    omit_batch_manifest: bool = False,
    omit_feature_csv: bool = False,
    omit_raw_files: bool = False,
    omit_run_files: set[str] | None = None,
    metadata_payload: dict[str, object] | None = None,
    run_manifest_payload: dict[str, object] | None = None,
    feature_rows: list[str] | None = None,
    extra_members: dict[str, str] | None = None,
) -> None:
    omit_run_files = omit_run_files or set()
    extra_members = extra_members or {}
    raw_prefix = f"{OFFICIAL_RELEASE_ROOT}/raw-evidence/verified-runs/{run_id}/"
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        if not omit_batch_manifest:
            runs = []
            if manifest_run_id is not None:
                runs.append(
                    {
                        "run_id": manifest_run_id,
                        "scenario": "AttackerHostLightDos",
                        "label": "DoS_DDoS",
                        "status": manifest_status,
                        "verification_status": verification_status,
                        "export_status": export_status,
                    }
                )
            archive.writestr(
                f"{OFFICIAL_RELEASE_ROOT}/batch-manifest/batch-manifest.json",
                json.dumps({"batch_id": "training-batch-20260607T132426Z", "runs": runs}),
            )
        if not omit_feature_csv:
            rows = feature_rows or [
                '"run_id","scenario","main_label","sublabel","is_clean_supervised_training_candidate"',
            ]
            if feature_rows is None and feature_row_run_id is not None:
                rows.append(
                    f'"{feature_row_run_id}","AttackerHostLightDos","DoS_DDoS",'
                    '"login_page_pressure","True"'
                )
            archive.writestr(
                f"{OFFICIAL_RELEASE_ROOT}/ml-features/training-batch-20260607T132426Z-features.csv",
                "\n".join(rows) + "\n",
            )
        if not omit_raw_files:
            metadata = metadata_payload or {
                "run_id": run_id,
                "scenario": "AttackerHostLightDos",
                "main_label": "DoS_DDoS",
                "sublabel": "login_page_pressure",
                "verification_passed": True,
                "clean_supervised_training_candidate": True,
            }
            run_manifest = run_manifest_payload or {
                "run_id": run_id,
                "scenario": "AttackerHostLightDos",
                "main_label": "DoS_DDoS",
                "sublabel": "login_page_pressure",
            }
            run_files = {
                "metadata.json": json.dumps(metadata),
                "manifest.json": json.dumps(run_manifest),
                "webapp-slice.log": "request completed\n",
                "nginx-access-slice.log": "GET / 200\n",
                "wazuh-evidence-summary.json": json.dumps({"archive_event_count": 1}),
                "wazuh-alerts-slice.json": json.dumps({"event": "alert"}) + "\n",
                "wazuh-archives-slice.json": json.dumps({"event": "archive"}) + "\n",
                "README.md": "# provenance\n",
            }
            for filename, content in run_files.items():
                if filename not in omit_run_files:
                    archive.writestr(f"{raw_prefix}{filename}", content)
        for name, content in extra_members.items():
            archive.writestr(name, content)


class OfficialRunVerifierTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmpdir.cleanup)
        self.zip_path = Path(self.tmpdir.name) / "fixture.zip"
        create_fixture_zip(self.zip_path)
        self.verifier = OfficialRunVerifier(
            release_zip_paths={OFFICIAL_RELEASE_ID: self.zip_path}
        )

    def test_valid_allowlisted_release_fixture(self) -> None:
        result = self.verifier.verify(OFFICIAL_RELEASE_ID, RUN_ID)

        self.assertTrue(result["verified"])
        self.assertEqual(result["state"], "verified")
        self.assertEqual(result["scenario"], "AttackerHostLightDos")
        self.assertEqual(result["label"], "DoS_DDoS")
        self.assertEqual(result["feature_oracle"]["usage"], "verification_only")

    def test_env_override_ignored_for_runtime_release_path(self) -> None:
        with patch.dict(os.environ, {"XDR_OFFICIAL_CLEAN_RELEASE_ZIP_PATH": str(self.zip_path)}):
            reloaded_config = reload(core_config)

        self.assertEqual(
            reloaded_config.OFFICIAL_CLEAN_RELEASE_ZIP_PATH.resolve(strict=False),
            reloaded_config.CANONICAL_OFFICIAL_CLEAN_RELEASE_ZIP_PATH.resolve(strict=False),
        )
        self.assertNotEqual(
            reloaded_config.OFFICIAL_CLEAN_RELEASE_ZIP_PATH.resolve(strict=False),
            self.zip_path.resolve(strict=False),
        )

    def test_runtime_default_verifier_enforces_canonical_release_path(self) -> None:
        verifier = OfficialRunVerifier()
        verifier.release_zip_paths[OFFICIAL_RELEASE_ID] = self.zip_path

        with self.assertRaises(OfficialRunRejection) as caught:
            verifier.verify(OFFICIAL_RELEASE_ID, RUN_ID)

        self.assertEqual(caught.exception.code, "release_path_not_canonical")

    def test_unknown_release_rejected(self) -> None:
        with self.assertRaises(OfficialRunRejection) as caught:
            self.verifier.verify("unknown-release", RUN_ID)

        self.assertEqual(caught.exception.code, "unknown_release")

    def test_preferred_official_run_if_zip_present(self) -> None:
        official_path = official_run_import_service.release_zip_paths[OFFICIAL_RELEASE_ID]
        if not official_path.exists():
            self.skipTest("official clean ZIP is not present in this checkout")

        result = official_run_import_service.verify(OFFICIAL_RELEASE_ID, RUN_ID)

        self.assertTrue(result["verified"])
        self.assertEqual(result["run_id"], RUN_ID)
        self.assertEqual(result["statuses"]["feature_oracle"], "present")

    def test_missing_run_rejected(self) -> None:
        with self.assertRaises(OfficialRunRejection) as caught:
            self.verifier.verify(OFFICIAL_RELEASE_ID, OTHER_RUN_ID)

        self.assertEqual(caught.exception.code, "run_not_found")

    def test_metadata_run_id_mismatch_rejected(self) -> None:
        create_fixture_zip(
            self.zip_path,
            metadata_payload={
                "run_id": OTHER_RUN_ID,
                "scenario": "AttackerHostLightDos",
                "main_label": "DoS_DDoS",
                "sublabel": "login_page_pressure",
            },
        )
        verifier = OfficialRunVerifier(release_zip_paths={OFFICIAL_RELEASE_ID: self.zip_path})

        with self.assertRaises(OfficialRunRejection) as caught:
            verifier.verify(OFFICIAL_RELEASE_ID, RUN_ID)

        self.assertEqual(caught.exception.code, "metadata_run_id_mismatch")

    def test_run_manifest_run_id_mismatch_rejected(self) -> None:
        create_fixture_zip(
            self.zip_path,
            run_manifest_payload={
                "run_id": OTHER_RUN_ID,
                "scenario": "AttackerHostLightDos",
                "main_label": "DoS_DDoS",
                "sublabel": "login_page_pressure",
            },
        )
        verifier = OfficialRunVerifier(release_zip_paths={OFFICIAL_RELEASE_ID: self.zip_path})

        with self.assertRaises(OfficialRunRejection) as caught:
            verifier.verify(OFFICIAL_RELEASE_ID, RUN_ID)

        self.assertEqual(caught.exception.code, "run_manifest_run_id_mismatch")

    def test_metadata_label_mismatch_rejected(self) -> None:
        create_fixture_zip(
            self.zip_path,
            metadata_payload={
                "run_id": RUN_ID,
                "scenario": "AttackerHostLightDos",
                "main_label": "Benign",
                "sublabel": "login_page_pressure",
            },
        )
        verifier = OfficialRunVerifier(release_zip_paths={OFFICIAL_RELEASE_ID: self.zip_path})

        with self.assertRaises(OfficialRunRejection) as caught:
            verifier.verify(OFFICIAL_RELEASE_ID, RUN_ID)

        self.assertEqual(caught.exception.code, "metadata_label_mismatch")

    def test_feature_oracle_scenario_mismatch_rejected(self) -> None:
        feature_rows = [
            '"run_id","scenario","main_label","sublabel","is_clean_supervised_training_candidate"',
            f'"{RUN_ID}","LightDos","DoS_DDoS","login_page_pressure","True"',
        ]
        create_fixture_zip(self.zip_path, feature_rows=feature_rows)
        verifier = OfficialRunVerifier(release_zip_paths={OFFICIAL_RELEASE_ID: self.zip_path})

        with self.assertRaises(OfficialRunRejection) as caught:
            verifier.verify(OFFICIAL_RELEASE_ID, RUN_ID)

        self.assertEqual(caught.exception.code, "feature_oracle_scenario_mismatch")

    def test_run_manifest_sublabel_mismatch_rejected(self) -> None:
        create_fixture_zip(
            self.zip_path,
            run_manifest_payload={
                "run_id": RUN_ID,
                "scenario": "AttackerHostLightDos",
                "main_label": "DoS_DDoS",
                "sublabel": "different_sublabel",
            },
        )
        verifier = OfficialRunVerifier(release_zip_paths={OFFICIAL_RELEASE_ID: self.zip_path})

        with self.assertRaises(OfficialRunRejection) as caught:
            verifier.verify(OFFICIAL_RELEASE_ID, RUN_ID)

        self.assertEqual(caught.exception.code, "run_manifest_sublabel_mismatch")

    def test_duplicate_feature_oracle_rows_rejected(self) -> None:
        feature_rows = [
            '"run_id","scenario","main_label","sublabel","is_clean_supervised_training_candidate"',
            f'"{RUN_ID}","AttackerHostLightDos","DoS_DDoS","login_page_pressure","True"',
            f'"{RUN_ID}","AttackerHostLightDos","DoS_DDoS","login_page_pressure","True"',
        ]
        create_fixture_zip(self.zip_path, feature_rows=feature_rows)
        verifier = OfficialRunVerifier(release_zip_paths={OFFICIAL_RELEASE_ID: self.zip_path})

        with self.assertRaises(OfficialRunRejection) as caught:
            verifier.verify(OFFICIAL_RELEASE_ID, RUN_ID)

        self.assertEqual(caught.exception.code, "feature_oracle_duplicate_row")

    def test_incomplete_run_rejected(self) -> None:
        create_fixture_zip(
            self.zip_path,
            run_id=INCOMPLETE_RUN_ID,
            manifest_run_id=INCOMPLETE_RUN_ID,
            feature_row_run_id=INCOMPLETE_RUN_ID,
        )
        verifier = OfficialRunVerifier(release_zip_paths={OFFICIAL_RELEASE_ID: self.zip_path})

        with self.assertRaises(OfficialRunRejection) as caught:
            verifier.verify(OFFICIAL_RELEASE_ID, INCOMPLETE_RUN_ID)

        self.assertEqual(caught.exception.code, "run_incomplete")

    def test_malformed_run_ids_rejected(self) -> None:
        bad_run_ids = [
            "",
            "../x",
            "/absolute-run",
            r"\absolute-run",
            "attackerhostlightdos-20260607T132426Z-201/manifest.json",
            r"attackerhostlightdos-20260607T132426Z-201\manifest.json",
            "C:attackerhostlightdos-20260607T132426Z-201",
            "attackerhostlightdos-20260607T132426Z-201\n",
            "a" * 129,
        ]
        for bad_run_id in bad_run_ids:
            with self.subTest(run_id=bad_run_id):
                with self.assertRaises(OfficialRunRejection) as caught:
                    self.verifier.verify(OFFICIAL_RELEASE_ID, bad_run_id)
                self.assertEqual(caught.exception.code, "invalid_run_id")

    def test_unsafe_zip_member_rejected(self) -> None:
        create_fixture_zip(
            self.zip_path,
            extra_members={f"{OFFICIAL_RELEASE_ROOT}/raw-evidence/../evil.json": "{}"},
        )
        verifier = OfficialRunVerifier(release_zip_paths={OFFICIAL_RELEASE_ID: self.zip_path})

        with self.assertRaises(OfficialRunRejection) as caught:
            verifier.verify(OFFICIAL_RELEASE_ID, RUN_ID)

        self.assertEqual(caught.exception.code, "unsafe_zip_member")

    def test_absolute_zip_member_rejected(self) -> None:
        create_fixture_zip(self.zip_path, extra_members={"/absolute.json": "{}"})
        verifier = OfficialRunVerifier(release_zip_paths={OFFICIAL_RELEASE_ID: self.zip_path})

        with self.assertRaises(OfficialRunRejection) as caught:
            verifier.verify(OFFICIAL_RELEASE_ID, RUN_ID)

        self.assertEqual(caught.exception.code, "unsafe_zip_member")

    def test_windows_drive_zip_member_rejected(self) -> None:
        create_fixture_zip(self.zip_path, extra_members={"C:/absolute.json": "{}"})
        verifier = OfficialRunVerifier(release_zip_paths={OFFICIAL_RELEASE_ID: self.zip_path})

        with self.assertRaises(OfficialRunRejection) as caught:
            verifier.verify(OFFICIAL_RELEASE_ID, RUN_ID)

        self.assertEqual(caught.exception.code, "unsafe_zip_member")

    def test_unsupported_extension_zip_member_rejected(self) -> None:
        create_fixture_zip(
            self.zip_path,
            extra_members={f"{OFFICIAL_RELEASE_ROOT}/raw-evidence/unsupported.exe": ""},
        )
        verifier = OfficialRunVerifier(release_zip_paths={OFFICIAL_RELEASE_ID: self.zip_path})

        with self.assertRaises(OfficialRunRejection) as caught:
            verifier.verify(OFFICIAL_RELEASE_ID, RUN_ID)

        self.assertEqual(caught.exception.code, "unsupported_zip_member")

    def test_unexpected_prefix_zip_member_rejected(self) -> None:
        create_fixture_zip(self.zip_path, extra_members={"other-root/file.json": "{}"})
        verifier = OfficialRunVerifier(release_zip_paths={OFFICIAL_RELEASE_ID: self.zip_path})

        with self.assertRaises(OfficialRunRejection) as caught:
            verifier.verify(OFFICIAL_RELEASE_ID, RUN_ID)

        self.assertEqual(caught.exception.code, "unexpected_zip_prefix")

    def test_unexpected_directory_prefix_rejected(self) -> None:
        create_fixture_zip(
            self.zip_path,
            extra_members={f"{OFFICIAL_RELEASE_ROOT}/not-allowed/": ""},
        )
        verifier = OfficialRunVerifier(release_zip_paths={OFFICIAL_RELEASE_ID: self.zip_path})

        with self.assertRaises(OfficialRunRejection) as caught:
            verifier.verify(OFFICIAL_RELEASE_ID, RUN_ID)

        self.assertEqual(caught.exception.code, "unexpected_zip_prefix")

    def test_release_root_directory_entry_allowed(self) -> None:
        create_fixture_zip(self.zip_path, extra_members={f"{OFFICIAL_RELEASE_ROOT}/": ""})
        verifier = OfficialRunVerifier(release_zip_paths={OFFICIAL_RELEASE_ID: self.zip_path})

        result = verifier.verify(OFFICIAL_RELEASE_ID, RUN_ID)

        self.assertTrue(result["verified"])

    def test_exact_duplicate_zip_member_rejected(self) -> None:
        duplicate_path = f"{OFFICIAL_RELEASE_ROOT}/raw-evidence/verified-runs/{RUN_ID}/metadata.json"
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            with zipfile.ZipFile(self.zip_path, "a", compression=zipfile.ZIP_DEFLATED) as archive:
                archive.writestr(duplicate_path, "{}")
        verifier = OfficialRunVerifier(release_zip_paths={OFFICIAL_RELEASE_ID: self.zip_path})

        with self.assertRaises(OfficialRunRejection) as caught:
            verifier.verify(OFFICIAL_RELEASE_ID, RUN_ID)

        self.assertEqual(caught.exception.code, "duplicate_zip_member")

    def test_duplicate_ambiguous_zip_member_rejected(self) -> None:
        duplicate_path = (
            f"{OFFICIAL_RELEASE_ROOT}\\raw-evidence\\verified-runs\\{RUN_ID}\\Metadata.json"
        )
        create_fixture_zip(self.zip_path, extra_members={duplicate_path: "{}"})
        verifier = OfficialRunVerifier(release_zip_paths={OFFICIAL_RELEASE_ID: self.zip_path})

        with self.assertRaises(OfficialRunRejection) as caught:
            verifier.verify(OFFICIAL_RELEASE_ID, RUN_ID)

        self.assertEqual(caught.exception.code, "duplicate_ambiguous_zip_member")

    def test_corrupt_synthetic_zip_rejected(self) -> None:
        self.zip_path.write_bytes(b"not a zip")
        verifier = OfficialRunVerifier(release_zip_paths={OFFICIAL_RELEASE_ID: self.zip_path})

        with self.assertRaises(OfficialRunRejection) as caught:
            verifier.verify(OFFICIAL_RELEASE_ID, RUN_ID)

        self.assertEqual(caught.exception.code, "corrupt_zip")

    def test_missing_batch_manifest_rejected(self) -> None:
        create_fixture_zip(self.zip_path, omit_batch_manifest=True)
        verifier = OfficialRunVerifier(release_zip_paths={OFFICIAL_RELEASE_ID: self.zip_path})

        with self.assertRaises(OfficialRunRejection) as caught:
            verifier.verify(OFFICIAL_RELEASE_ID, RUN_ID)

        self.assertEqual(caught.exception.code, "zip_member_missing")

    def test_missing_run_manifest_rejected(self) -> None:
        create_fixture_zip(self.zip_path, omit_run_files={"manifest.json"})
        verifier = OfficialRunVerifier(release_zip_paths={OFFICIAL_RELEASE_ID: self.zip_path})

        with self.assertRaises(OfficialRunRejection) as caught:
            verifier.verify(OFFICIAL_RELEASE_ID, RUN_ID)

        self.assertEqual(caught.exception.code, "manifest_missing")

    def test_missing_raw_evidence_directory_rejected(self) -> None:
        create_fixture_zip(self.zip_path, omit_raw_files=True)
        verifier = OfficialRunVerifier(release_zip_paths={OFFICIAL_RELEASE_ID: self.zip_path})

        with self.assertRaises(OfficialRunRejection) as caught:
            verifier.verify(OFFICIAL_RELEASE_ID, RUN_ID)

        self.assertEqual(caught.exception.code, "raw_evidence_missing")

    def test_missing_feature_oracle_row_rejected(self) -> None:
        create_fixture_zip(self.zip_path, feature_row_run_id=None)
        verifier = OfficialRunVerifier(release_zip_paths={OFFICIAL_RELEASE_ID: self.zip_path})

        with self.assertRaises(OfficialRunRejection) as caught:
            verifier.verify(OFFICIAL_RELEASE_ID, RUN_ID)

        self.assertEqual(caught.exception.code, "feature_oracle_row_missing")

    def test_oversized_entry_rejected(self) -> None:
        verifier = OfficialRunVerifier(
            release_zip_paths={OFFICIAL_RELEASE_ID: self.zip_path},
            max_entry_bytes=8,
        )

        with self.assertRaises(OfficialRunRejection) as caught:
            verifier.verify(OFFICIAL_RELEASE_ID, RUN_ID)

        self.assertEqual(caught.exception.code, "zip_entry_oversized")

    def test_archive_member_count_limit_rejected(self) -> None:
        verifier = OfficialRunVerifier(
            release_zip_paths={OFFICIAL_RELEASE_ID: self.zip_path},
            max_member_count=1,
        )

        with self.assertRaises(OfficialRunRejection) as caught:
            verifier.verify(OFFICIAL_RELEASE_ID, RUN_ID)

        self.assertEqual(caught.exception.code, "zip_member_count_exceeded")

    def test_archive_total_uncompressed_size_limit_rejected(self) -> None:
        verifier = OfficialRunVerifier(
            release_zip_paths={OFFICIAL_RELEASE_ID: self.zip_path},
            max_total_uncompressed_bytes=32,
        )

        with self.assertRaises(OfficialRunRejection) as caught:
            verifier.verify(OFFICIAL_RELEASE_ID, RUN_ID)

        self.assertEqual(caught.exception.code, "zip_total_size_exceeded")

    def test_excessive_read_budget_rejected(self) -> None:
        verifier = OfficialRunVerifier(
            release_zip_paths={OFFICIAL_RELEASE_ID: self.zip_path},
            total_read_budget_bytes=32,
        )

        with self.assertRaises(OfficialRunRejection) as caught:
            verifier.verify(OFFICIAL_RELEASE_ID, RUN_ID)

        self.assertEqual(caught.exception.code, "zip_read_budget_exceeded")

    def test_feature_oracle_not_returned_as_feature_vector(self) -> None:
        result = self.verifier.verify(OFFICIAL_RELEASE_ID, RUN_ID)
        rendered = json.dumps(result)

        self.assertEqual(set(result["feature_oracle"]), {"status", "usage", "clean_supervised_training_candidate"})
        self.assertNotIn("base_features", rendered)
        self.assertNotIn("feature_vector", rendered)
        self.assertNotIn("request_completed_count", rendered)

    def test_no_official_zip_mutation(self) -> None:
        official_path = official_run_import_service.release_zip_paths[OFFICIAL_RELEASE_ID]
        if not official_path.exists():
            self.skipTest("official clean ZIP is not present in this checkout")
        before = official_path.stat()

        official_run_import_service.verify(OFFICIAL_RELEASE_ID, RUN_ID)

        after = official_path.stat()
        self.assertEqual(before.st_size, after.st_size)
        self.assertEqual(before.st_mtime_ns, after.st_mtime_ns)


class OfficialRunEndpointTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmpdir.cleanup)
        self.zip_path = Path(self.tmpdir.name) / "fixture.zip"
        create_fixture_zip(self.zip_path)
        self.verifier = OfficialRunVerifier(
            release_zip_paths={OFFICIAL_RELEASE_ID: self.zip_path}
        )
        self.client = TestClient(main.app)

    def post_import(self, *, token: str | None = "secret", payload: dict[str, str] | None = None):
        headers = {}
        if token is not None:
            headers["Authorization"] = f"Bearer {token}"
        return self.client.post(
            "/api/official-runs/import",
            headers=headers,
            json=payload or {"release_id": OFFICIAL_RELEASE_ID, "run_id": RUN_ID},
        )

    def test_disabled_demo_import_rejected(self) -> None:
        with patch.object(main, "XDR_DEMO_IMPORT_ENABLED", False), patch.object(
            main, "XDR_DEMO_API_TOKEN", "secret"
        ):
            response = self.post_import()

        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json()["detail"]["rejection"]["code"], "demo_import_disabled")

    def test_missing_token_rejected(self) -> None:
        with patch.object(main, "XDR_DEMO_IMPORT_ENABLED", True), patch.object(
            main, "XDR_DEMO_API_TOKEN", "secret"
        ):
            response = self.post_import(token=None)

        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.json()["detail"]["rejection"]["code"], "demo_import_token_missing")

    def test_invalid_token_rejected(self) -> None:
        with patch.object(main, "XDR_DEMO_IMPORT_ENABLED", True), patch.object(
            main, "XDR_DEMO_API_TOKEN", "secret"
        ):
            response = self.post_import(token="wrong")

        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json()["detail"]["rejection"]["code"], "demo_import_token_invalid")
        self.assertNotIn("wrong", json.dumps(response.json()))

    def test_valid_token_allows_verification(self) -> None:
        with patch.object(main, "XDR_DEMO_IMPORT_ENABLED", True), patch.object(
            main, "XDR_DEMO_API_TOKEN", "secret"
        ), patch.object(main, "official_run_import_service", self.verifier):
            response = self.post_import()

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()["verified"])

    def test_no_absolute_local_paths_in_api_response(self) -> None:
        with patch.object(main, "XDR_DEMO_IMPORT_ENABLED", True), patch.object(
            main, "XDR_DEMO_API_TOKEN", "secret"
        ), patch.object(main, "official_run_import_service", self.verifier):
            response = self.post_import()

        self.assertEqual(response.status_code, 200)
        self.assertNotIn(str(self.zip_path), json.dumps(response.json()))
        self.assertNotIn(str(Path(self.tmpdir.name)), json.dumps(response.json()))

    def test_request_extras_rejected(self) -> None:
        with patch.object(main, "XDR_DEMO_IMPORT_ENABLED", True), patch.object(
            main, "XDR_DEMO_API_TOKEN", "secret"
        ), patch.object(main, "official_run_import_service", self.verifier):
            response = self.post_import(
                payload={
                    "release_id": OFFICIAL_RELEASE_ID,
                    "run_id": RUN_ID,
                    "model_name": "ebm",
                }
            )

        self.assertEqual(response.status_code, 422)


if __name__ == "__main__":
    unittest.main()
