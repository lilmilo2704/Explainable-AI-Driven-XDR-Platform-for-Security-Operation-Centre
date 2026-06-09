# Coding Fest 2026 XDR Dataset Release

Batch ID: $batchId

## Scope

This package contains the clean portable release for the Coding Fest 2026 XDR/SIEM lab dataset batch $batchId. The current ML scope is run-level and window-level classification for:

- Benign
- DoS_DDoS

LightDos and AttackerHostLightDos are mapped to the DoS_DDoS label. This dataset is mostly bounded single-source DoS/service-stress evidence, so do not describe it as complete real-world multi-source DDoS coverage.

## Label Distribution

- Benign: 100 rows
- DoS_DDoS: 200 rows

The raw evidence folder excludes the known incomplete run enign-20260607T132426Z-043, so it contains 299 verified-run folders even though the tabular dataset files retain 300 rows.

## Main Files

- Main training file: model-ready\training-batch-20260607T132426Z-model-ready-run-level.csv
- Windowed file: windowed-dataset\training-batch-20260607T132426Z-windows.csv
- Feature export: ml-features\training-batch-20260607T132426Z-features.csv
- Quality summary: quality-summary\training-batch-20260607T132426Z-quality-summary.csv
- Batch manifest: atch-manifest\batch-manifest.json
- Raw evidence location: aw-evidence\verified-runs\<run_id>\

## Training Guidance

For clean supervised training, exclude rows where is_clean_supervised_training_candidate is False.

The known incomplete run is enign-20260607T132426Z-043. It is intentionally excluded from aw-evidence\verified-runs\.

## Evidence Notes

Wazuh archive files in the raw evidence folders are Wazuh-collected and enriched evidence. They are not exact raw endpoint logs only. Endpoint and service slices such as web app, nginx, and auth logs are included separately when available in each verified-run folder.

All paths inside this package are package-relative and intended to work after extraction on another machine.
