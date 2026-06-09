<#
.SYNOPSIS
Builds leakage-reduced model-ready CSV/JSON exports from existing feature tables.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BatchManifestPath,

    [string]$OutputDir = "exports\model-ready",

    [switch]$IncludeWindowed,

    [string]$WindowedDatasetPath
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Path (Split-Path -Path $MyInvocation.MyCommand.Path -Parent) -Parent

function Resolve-PathInRepo {
    param([string]$Path)
    if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
    return [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
}

function Get-FeatureInputPath {
    param([string]$BatchId)
    $path = Join-Path (Resolve-PathInRepo "exports\ml-features") "$BatchId-features.csv"
    if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
    throw "Feature table not found: $path. Run scripts\build-ml-feature-table.ps1 first."
}

function Remove-LeakageColumns {
    param(
        [object[]]$Rows,
        [string[]]$RemoveColumns
    )

    $cleanRows = New-Object System.Collections.Generic.List[object]
    foreach ($row in $Rows) {
        $ordered = [ordered]@{}
        foreach ($prop in $row.PSObject.Properties) {
            if ($RemoveColumns -contains $prop.Name) { continue }
            if ($prop.Name -match "(?i)path$|_path$|raw|evidence_text|log_text|source_ip$|dominant_source_ip|attacker_source_ip") { continue }
            $ordered[$prop.Name] = $prop.Value
        }
        $cleanRows.Add([PSCustomObject]$ordered) | Out-Null
    }
    return @($cleanRows.ToArray())
}

$resolvedBatch = Resolve-PathInRepo $BatchManifestPath
$batch = Get-Content -Raw -LiteralPath $resolvedBatch | ConvertFrom-Json
$batchId = [string]$batch.batch_id
$resolvedOutputDir = Resolve-PathInRepo $OutputDir
New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null

$featurePath = Get-FeatureInputPath -BatchId $batchId
$rows = @(Import-Csv -LiteralPath $featurePath)

$removeColumns = @(
    "run_id",
    "scenario",
    "sublabel",
    "scenario_variant",
    "actor_profile",
    "benign_activity_level",
    "generator_version",
    "target_endpoint_family",
    "attacker_source_ip",
    "attack_mode",
    "dominant_source_ip",
    "verified_run_dir",
    "manifest_path",
    "metadata_path",
    "webapp_slice_path",
    "nginx_access_slice_path",
    "auth_slice_path",
    "wazuh_archives_slice_path",
    "wazuh_alerts_slice_path",
    "wazuh_evidence_summary_path"
)

$cleanRows = Remove-LeakageColumns -Rows $rows -RemoveColumns $removeColumns
$csvPath = Join-Path $resolvedOutputDir "$batchId-model-ready-run-level.csv"
$jsonPath = Join-Path $resolvedOutputDir "$batchId-model-ready-run-level.json"
$removedPath = Join-Path $resolvedOutputDir "$batchId-removed-columns.json"
$dictionaryPath = Join-Path $resolvedOutputDir "$batchId-data-dictionary.md"

$cleanRows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
$cleanRows | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

[ordered]@{
    batch_id = $batchId
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    source_feature_table = $featurePath
    target_column = "main_label"
    explicitly_removed_columns = $removeColumns
    pattern_removed_columns = @("file/path columns", "raw evidence/log text", "string IP address columns")
    notes = @(
        "Scenario names, source IP strings, raw logs, paths, and metadata identifiers are removed from model input.",
        "main_label is preserved as the target label.",
        "Do not treat this as model training; this script only prepares data for the ML teammate."
    )
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $removedPath -Encoding UTF8

$columns = if ($cleanRows.Count -gt 0) { @($cleanRows[0].PSObject.Properties.Name) } else { @() }
$columnLines = ($columns | ForEach-Object { "- ``$_``" }) -join "`r`n"
@"
# Model-Ready Data Dictionary - $batchId

Target column: `main_label`

This export removes known leakage/provenance columns and raw/path/IP string fields. It is intended for a first baseline classifier handoff, not for final public-quality modelling.

## Columns

$columnLines

## Removed Families

- Scenario and sublabel identifiers.
- Actor/scenario variant metadata.
- Run IDs and file paths.
- Raw evidence text.
- String IP addresses.
- Direct attack-mode metadata.

Wazuh counts are retained as numeric evidence-volume features. Wazuh alerts are not labels.
"@ | Set-Content -LiteralPath $dictionaryPath -Encoding UTF8

if ($IncludeWindowed) {
    if ([string]::IsNullOrWhiteSpace($WindowedDatasetPath)) {
        $WindowedDatasetPath = Join-Path (Resolve-PathInRepo "exports\windowed-datasets") "$batchId-windows.csv"
    }
    $resolvedWindowed = Resolve-PathInRepo $WindowedDatasetPath
    if (Test-Path -LiteralPath $resolvedWindowed -PathType Leaf) {
        $windowRows = @(Import-Csv -LiteralPath $resolvedWindowed)
        $windowRemove = $removeColumns + @("window_id", "window_start_utc", "window_end_utc", "stage_label", "raw_evidence_refs", "dominant_source_ip")
        $cleanWindowRows = Remove-LeakageColumns -Rows $windowRows -RemoveColumns $windowRemove
        $windowCsv = Join-Path $resolvedOutputDir "$batchId-model-ready-window-level.csv"
        $windowJson = Join-Path $resolvedOutputDir "$batchId-model-ready-window-level.json"
        $cleanWindowRows | Export-Csv -LiteralPath $windowCsv -NoTypeInformation -Encoding UTF8
        $cleanWindowRows | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $windowJson -Encoding UTF8
        Write-Host "Window-level model-ready CSV: $windowCsv"
    }
    else {
        Write-Host "Windowed dataset not found; skipped IncludeWindowed output: $resolvedWindowed" -ForegroundColor Yellow
    }
}

Write-Host "Run-level model-ready CSV: $csvPath"
Write-Host "Run-level model-ready JSON: $jsonPath"
Write-Host "Removed columns: $removedPath"
Write-Host "Data dictionary: $dictionaryPath"
