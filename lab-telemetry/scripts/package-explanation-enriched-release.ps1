<#
.SYNOPSIS
Packages the official dataset with explanation labels into a clean release.

.DESCRIPTION
Creates an explanation-enriched release folder from the existing clean official
dataset release, adds explanation-label and model-ready-explanation outputs,
adds release-level documentation, validates the package, and creates a zip file.
#>

[CmdletBinding()]
param(
    [string]$BatchId = "training-batch-20260607T132426Z",

    [string]$ReleaseRoot = "exports\dataset-releases",

    [switch]$Force
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Path (Split-Path -Path $MyInvocation.MyCommand.Path -Parent) -Parent

function Resolve-PathInRepo {
    param([string]$Path)
    if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
    return [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
}

function Ensure-CleanTarget {
    param([string]$Path, [string]$AllowedRoot, [switch]$Force)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    if (-not $Force) { throw "Target already exists. Use -Force to replace: $Path" }

    $resolvedTarget = [System.IO.Path]::GetFullPath($Path)
    $resolvedRoot = [System.IO.Path]::GetFullPath($AllowedRoot)
    if (-not $resolvedTarget.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove target outside release root: $resolvedTarget"
    }
    Remove-Item -LiteralPath $resolvedTarget -Recurse -Force
}

function Copy-Directory {
    param([string]$Source, [string]$Destination)
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) { throw "Missing source directory: $Source" }
    New-Item -ItemType Directory -Force -Path (Split-Path -Path $Destination -Parent) | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
}

function Copy-BatchFiles {
    param([string]$SourceDir, [string]$DestinationDir, [string]$BatchId)
    if (-not (Test-Path -LiteralPath $SourceDir -PathType Container)) { throw "Missing source directory: $SourceDir" }
    New-Item -ItemType Directory -Force -Path $DestinationDir | Out-Null
    $files = @(Get-ChildItem -LiteralPath $SourceDir -File | Where-Object { $_.Name -like "$BatchId*" })
    if ($files.Count -eq 0) { throw "No batch files found in $SourceDir for $BatchId" }
    foreach ($file in $files) {
        Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $DestinationDir $file.Name) -Force
    }
}

function Write-ReleaseFile {
    param([string]$Path, [string]$Content)
    New-Item -ItemType Directory -Force -Path (Split-Path -Path $Path -Parent) | Out-Null
    $Content | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Sanitize-ReleaseTextFiles {
    param([string]$ReleaseDir, [string]$LocalPath)
    $extensions = @(".csv", ".json", ".log", ".md", ".txt")
    $files = @(Get-ChildItem -LiteralPath $ReleaseDir -Recurse -File | Where-Object { $extensions -contains $_.Extension.ToLowerInvariant() })
    $escapedLocal = [regex]::Escape($LocalPath)
    foreach ($file in $files) {
        $content = Get-Content -LiteralPath $file.FullName -Raw
        $updated = $content -replace $escapedLocal, "."
        $updated = $updated -replace [regex]::Escape(($LocalPath -replace "\\", "/")), "."
        if ($updated -ne $content) {
            $updated | Set-Content -LiteralPath $file.FullName -Encoding UTF8
        }
    }
}

function Get-DirectorySizeBytes {
    param([string]$Path)
    $measure = Get-ChildItem -LiteralPath $Path -Recurse -File | Measure-Object -Property Length -Sum
    return [int64]$measure.Sum
}

function Format-Bytes {
    param([int64]$Bytes)
    if ($Bytes -ge 1GB) { return ("{0:N2} GB" -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ("{0:N2} MB" -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ("{0:N2} KB" -f ($Bytes / 1KB)) }
    return "$Bytes bytes"
}

$releaseRootPath = Resolve-PathInRepo $ReleaseRoot
$cleanReleaseName = "coding-fest-2026-xdr-dataset-$BatchId-clean"
$releaseName = "coding-fest-2026-xdr-dataset-$BatchId-explanation-enriched"
$cleanReleaseDir = Join-Path $releaseRootPath $cleanReleaseName
$releaseDir = Join-Path $releaseRootPath $releaseName
$zipPath = "$releaseDir.zip"

if (-not (Test-Path -LiteralPath $cleanReleaseDir -PathType Container)) {
    throw "Clean release source not found: $cleanReleaseDir"
}

Ensure-CleanTarget -Path $releaseDir -AllowedRoot $releaseRootPath -Force:$Force
Ensure-CleanTarget -Path $zipPath -AllowedRoot $releaseRootPath -Force:$Force
New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null

Copy-Directory -Source (Join-Path $cleanReleaseDir "batch-manifest") -Destination (Join-Path $releaseDir "batch-manifest")
Copy-Directory -Source (Join-Path $cleanReleaseDir "quality-summary") -Destination (Join-Path $releaseDir "dataset-quality")
Copy-Directory -Source (Join-Path $cleanReleaseDir "ml-features") -Destination (Join-Path $releaseDir "ml-features")
Copy-Directory -Source (Join-Path $cleanReleaseDir "model-ready") -Destination (Join-Path $releaseDir "model-ready")
Copy-Directory -Source (Join-Path $cleanReleaseDir "windowed-dataset") -Destination (Join-Path $releaseDir "windowed-dataset")
Copy-Directory -Source (Join-Path $cleanReleaseDir "raw-evidence") -Destination (Join-Path $releaseDir "raw-evidence")

Copy-BatchFiles -SourceDir (Resolve-PathInRepo "exports\explanation-labels") -DestinationDir (Join-Path $releaseDir "explanation-labels") -BatchId $BatchId
Copy-BatchFiles -SourceDir (Resolve-PathInRepo "exports\model-ready-explanation") -DestinationDir (Join-Path $releaseDir "model-ready-explanation") -BatchId $BatchId

$documentationDir = Join-Path $releaseDir "documentation"
New-Item -ItemType Directory -Force -Path $documentationDir | Out-Null
$documentationSources = @(
    @{ Source = "AGENTS.md"; Destination = "AGENTS.md" },
    @{ Source = "README.md"; Destination = "PROJECT_README.md" },
    @{ Source = "docs\00_PROJECT_CONTEXT_SUMMARY.md"; Destination = "00_PROJECT_CONTEXT_SUMMARY.md" },
    @{ Source = "docs\10_CODEX_NEXT_TASKS.md"; Destination = "10_CODEX_NEXT_TASKS.md" },
    @{ Source = "docs\11_CONTROLLED_TELEMETRY_RUNBOOK.md"; Destination = "11_CONTROLLED_TELEMETRY_RUNBOOK.md" },
    @{ Source = "docs\CODEX_CURRENT_STATUS_HANDOFF.md"; Destination = "CODEX_CURRENT_STATUS_HANDOFF.md" }
)
foreach ($doc in $documentationSources) {
    $sourcePath = Resolve-PathInRepo $doc.Source
    if (Test-Path -LiteralPath $sourcePath -PathType Leaf) {
        Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $documentationDir $doc.Destination) -Force
    }
}

$readmeTemplate = @'
# Coding Fest 2026 XDR Dataset - Explanation-Enriched Release

Batch ID: __BATCH_ID__

This release packages the official clean Wazuh-linked XDR dataset with the new explanation-labelling layer.

Project framing: a log-centric, Wazuh-linked XDR dataset and prototype pipeline for detecting and explaining application-layer DoS/DDoS/service-stress incidents using server-side logs, web application logs, nginx logs, Wazuh archives, Wazuh alerts, and windowed behaviour features.

## Contents

- `batch-manifest/`
- `dataset-quality/`
- `ml-features/`
- `model-ready/`
- `windowed-dataset/`
- `raw-evidence/`
- `explanation-labels/`
- `model-ready-explanation/`
- `documentation/`

## Label Policy

The original detection labels are controlled lab labels.

The new `stage_label`, `evidence_role`, and `evidence_score` fields are AI-assisted/rule-assisted weak explanation labels. They are intended for explanation-model prototyping and should not be described as fully manually verified human ground truth.

Labels include `label_source`, `label_confidence`, `label_reason`, and `needs_human_review` for transparency.

## Dataset Scale

- 300 tabular runs
- 100 Benign runs
- 100 LightDos runs
- 100 AttackerHostLightDos runs
- 200 DoS_DDoS-labelled runs total
- 798 windowed rows
- 300 model-ready run-level rows
- 299 raw verified-run evidence folders

`benign-20260607T132426Z-043` is the known incomplete run. It failed verification/export and is intentionally missing from raw evidence. This is expected and is not a packaging bug.

## Best Use

Use the run-level and windowed datasets for controlled detection experiments. Use the explanation-label and model-ready-explanation datasets for stage classification, evidence attribution, incident storyline graph prototypes, and SOC-style explanation report prototypes.

For clean supervised training on the original labels, use `is_clean_supervised_training_candidate == True` where present.
'@
$readme = $readmeTemplate.Replace("__BATCH_ID__", $BatchId)

$limitations = @'
# Limitations

- This is a controlled lab-generated dataset, not production real-world traffic.
- Most attack traffic is single-source DoS/service-stress, not true distributed DDoS.
- `DoS_DDoS` is a high-level controlled lab label for the current ML handoff.
- `AttackerHostLightDos` should not be described as true DDoS unless multiple visible source IPs exist in victim logs.
- The dataset is log-centric and Wazuh-linked. It does not include packet capture.
- Public packet/flow datasets should not be directly merged into this Wazuh lab dataset without a separate external-normalized layer.
- Explanation labels are AI-assisted/rule-assisted weak labels, not fully manually verified human ground truth.
- `service_degradation` should only be used when explicit degradation evidence exists, such as 5xx status, failed health check, timeout, service unavailable, connection refused, nginx error, or severe latency spike.
- `benign-20260607T132426Z-043` is known incomplete and intentionally absent from raw evidence.
'@

$explanationGuide = @'
# Explanation Label Guide

## Stage Labels

- `baseline`: normal or benign baseline activity.
- `burst_onset`: first high request-rate or burst-search window in a DoS_DDoS run.
- `sustained_pressure`: later high request-rate windows.
- `service_stress`: high request volume paired with stress indicators.
- `service_degradation`: explicit degradation evidence only.
- `recovery`: post-pressure recovery window when available.
- `unclear`: insufficient or ambiguous evidence.

## Evidence Roles

- `baseline_sample`
- `representative_burst_request`
- `source_concentration_evidence`
- `distributed_source_evidence`
- `sustained_pressure_evidence`
- `service_stress_evidence`
- `latency_evidence`
- `error_evidence`
- `health_check_failure`
- `nginx_access_evidence`
- `webapp_request_completion`
- `wazuh_confirmation`
- `wazuh_alert_context`
- `irrelevant`

## Evidence Score

- `0`: irrelevant
- `1`: weak supporting evidence
- `2`: useful supporting evidence
- `3`: strong evidence that should appear in an incident graph or report

## Transparency Columns

Every generated explanation row includes:

- `label_source`
- `label_confidence`
- `label_reason`
- `needs_human_review`

Current label source values include `rule_based`, with reserved support for `codex_assisted` and `human_reviewed`.

Rows marked `unclear`, low-confidence, or degradation-related should be manually reviewed.
'@

$structureTemplate = @'
# Dataset Structure

```text
__RELEASE_NAME__/
  README.md
  LIMITATIONS.md
  EXPLANATION_LABEL_GUIDE.md
  DATASET_STRUCTURE.md
  batch-manifest/
    batch-manifest.json
    README.md
  dataset-quality/
    __BATCH_ID__-quality-summary.csv
    __BATCH_ID__-quality-summary.json
  ml-features/
    __BATCH_ID__-features.csv
    __BATCH_ID__-features.json
  model-ready/
    __BATCH_ID__-model-ready-run-level.csv
    __BATCH_ID__-model-ready-run-level.json
    __BATCH_ID__-data-dictionary.md
    __BATCH_ID__-removed-columns.json
  windowed-dataset/
    __BATCH_ID__-windows.csv
    __BATCH_ID__-windows.json
    __BATCH_ID__-window-build-summary.json
  raw-evidence/
    verified-runs/
      <run_id>/
        metadata.json
        manifest.json
        README.md
        auth-slice.log
        webapp-slice.log
        nginx-access-slice.log
        wazuh-archives-slice.json
        wazuh-alerts-slice.json
        wazuh-evidence-summary.json
  explanation-labels/
    __BATCH_ID__-stage-labels.csv
    __BATCH_ID__-evidence-labels.csv
    __BATCH_ID__-label-summary.json
    __BATCH_ID__-LABEL_GUIDE.md
    __BATCH_ID__-EXPLANATION_LABEL_QUALITY_REPORT.md
    __BATCH_ID__-explanation-label-quality-report.json
  model-ready-explanation/
    __BATCH_ID__-stage-classification.csv
    __BATCH_ID__-evidence-attribution.csv
    __BATCH_ID__-evidence-attribution-with-text.csv
    __BATCH_ID__-explanation-data-dictionary.md
    __BATCH_ID__-explanation-summary.json
  documentation/
    <project context markdown files>
```

All paths are relative to the release folder.
'@
$structure = $structureTemplate.Replace("__BATCH_ID__", $BatchId).Replace("__RELEASE_NAME__", $releaseName)

Write-ReleaseFile -Path (Join-Path $releaseDir "README.md") -Content $readme
Write-ReleaseFile -Path (Join-Path $releaseDir "LIMITATIONS.md") -Content $limitations
Write-ReleaseFile -Path (Join-Path $releaseDir "EXPLANATION_LABEL_GUIDE.md") -Content $explanationGuide
Write-ReleaseFile -Path (Join-Path $releaseDir "DATASET_STRUCTURE.md") -Content $structure

Sanitize-ReleaseTextFiles -ReleaseDir $releaseDir -LocalPath $RepoRoot

$expectedPaths = @(
    "README.md",
    "LIMITATIONS.md",
    "EXPLANATION_LABEL_GUIDE.md",
    "DATASET_STRUCTURE.md",
    "batch-manifest\batch-manifest.json",
    "dataset-quality\$BatchId-quality-summary.csv",
    "dataset-quality\$BatchId-quality-summary.json",
    "ml-features\$BatchId-features.csv",
    "ml-features\$BatchId-features.json",
    "model-ready\$BatchId-model-ready-run-level.csv",
    "model-ready\$BatchId-model-ready-run-level.json",
    "model-ready\$BatchId-data-dictionary.md",
    "model-ready\$BatchId-removed-columns.json",
    "windowed-dataset\$BatchId-windows.csv",
    "windowed-dataset\$BatchId-windows.json",
    "windowed-dataset\$BatchId-window-build-summary.json",
    "raw-evidence\verified-runs",
    "explanation-labels\$BatchId-stage-labels.csv",
    "explanation-labels\$BatchId-evidence-labels.csv",
    "explanation-labels\$BatchId-label-summary.json",
    "explanation-labels\$BatchId-LABEL_GUIDE.md",
    "explanation-labels\$BatchId-EXPLANATION_LABEL_QUALITY_REPORT.md",
    "explanation-labels\$BatchId-explanation-label-quality-report.json",
    "model-ready-explanation\$BatchId-stage-classification.csv",
    "model-ready-explanation\$BatchId-evidence-attribution.csv",
    "model-ready-explanation\$BatchId-evidence-attribution-with-text.csv",
    "model-ready-explanation\$BatchId-explanation-data-dictionary.md",
    "model-ready-explanation\$BatchId-explanation-summary.json",
    "documentation"
)

$missingExpectedPaths = @($expectedPaths | Where-Object { -not (Test-Path -LiteralPath (Join-Path $releaseDir $_)) })
$absolutePathMatches = @(Get-ChildItem -LiteralPath $releaseDir -Recurse -File | Select-String -SimpleMatch $RepoRoot -List)
$exportsOriginalMatches = @(Get-ChildItem -LiteralPath $releaseDir -Recurse -Force | Where-Object { $_.Name -match 'exports-original' })
$rawRunDirs = @(Get-ChildItem -LiteralPath (Join-Path $releaseDir "raw-evidence\verified-runs") -Directory)
$benign043Path = Join-Path $releaseDir "raw-evidence\verified-runs\benign-20260607T132426Z-043"
$benign043Documented = @(Get-ChildItem -LiteralPath $releaseDir -Recurse -File -Include *.md,*.json,*.txt | Select-String -SimpleMatch "benign-20260607T132426Z-043" -List).Count -gt 0

$validation = [ordered]@{
    no_local_absolute_paths = ($absolutePathMatches.Count -eq 0)
    local_absolute_path_match_count = $absolutePathMatches.Count
    no_exports_original_folders = ($exportsOriginalMatches.Count -eq 0)
    exports_original_match_count = $exportsOriginalMatches.Count
    raw_evidence_folder_count = $rawRunDirs.Count
    raw_evidence_folder_count_expected = 299
    raw_evidence_folder_count_ok = ($rawRunDirs.Count -eq 299)
    benign_043_missing_from_raw_evidence = (-not (Test-Path -LiteralPath $benign043Path))
    benign_043_documented = $benign043Documented
    referenced_relative_paths_exist = ($missingExpectedPaths.Count -eq 0)
    missing_referenced_relative_paths = @($missingExpectedPaths)
}

if (-not $validation.no_local_absolute_paths) { throw "Validation failed: local absolute paths remain in release." }
if (-not $validation.no_exports_original_folders) { throw "Validation failed: exports-original folder found in release." }
if (-not $validation.raw_evidence_folder_count_ok) { throw "Validation failed: expected 299 raw evidence folders, found $($rawRunDirs.Count)." }
if (-not $validation.benign_043_missing_from_raw_evidence) { throw "Validation failed: benign-043 raw evidence folder should be absent." }
if (-not $validation.benign_043_documented) { throw "Validation failed: benign-043 is not documented." }
if (-not $validation.referenced_relative_paths_exist) { throw "Validation failed: missing expected release paths: $($missingExpectedPaths -join ', ')" }

$validationReport = [ordered]@{
    batch_id = $BatchId
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    release_folder = $releaseName
    zip_file = "$releaseName.zip"
    file_count = $null
    folder_size_bytes = $null
    folder_size_human = $null
    zip_size_bytes = "computed after archive creation"
    zip_size_human = "computed after archive creation"
    validation = $validation
}
$validationPath = Join-Path $releaseDir "RELEASE_VALIDATION.json"
$validationReport | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $validationPath -Encoding UTF8

$fileCount = @(Get-ChildItem -LiteralPath $releaseDir -Recurse -File).Count
$folderSizeBytes = Get-DirectorySizeBytes -Path $releaseDir
$validationReport.file_count = $fileCount
$validationReport.folder_size_bytes = $folderSizeBytes
$validationReport.folder_size_human = Format-Bytes $folderSizeBytes
$validationReport | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $validationPath -Encoding UTF8

$postValidationAbsolutePathMatches = @(Get-ChildItem -LiteralPath $releaseDir -Recurse -File | Select-String -SimpleMatch $RepoRoot -List)
if ($postValidationAbsolutePathMatches.Count -gt 0) {
    throw "Validation failed after writing release validation: local absolute paths remain in release."
}

Compress-Archive -LiteralPath $releaseDir -DestinationPath $zipPath -CompressionLevel Optimal -Force
$zipSizeBytes = (Get-Item -LiteralPath $zipPath).Length

Write-Host "Explanation-enriched release created."
Write-Host "Release folder: $releaseDir"
Write-Host "Zip path: $zipPath"
Write-Host "File count: $fileCount"
Write-Host "Folder size: $(Format-Bytes $folderSizeBytes)"
Write-Host "Zip size: $(Format-Bytes $zipSizeBytes)"
Write-Host "Raw evidence folders: $($rawRunDirs.Count)"
Write-Host "Validation: PASS"
