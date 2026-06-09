<#
.SYNOPSIS
Builds model-ready explanation datasets from generated explanation labels.

.DESCRIPTION
Reads stage/evidence explanation label CSV files and writes compact
stage-classification and evidence-attribution datasets. The default evidence
dataset excludes full event text to reduce size and leakage risk; a separate
with-text CSV is produced for traceability and review.
#>

[CmdletBinding()]
param(
    [string]$BatchId = "training-batch-20260607T132426Z",

    [string]$InputDir = "exports\explanation-labels",

    [string]$OutputDir = "exports\model-ready-explanation",

    [switch]$ExcludeNeedsHumanReview,

    [switch]$Force
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Path (Split-Path -Path $MyInvocation.MyCommand.Path -Parent) -Parent

function Resolve-PathInRepo {
    param([string]$Path)
    if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
    return [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
}

function Convert-ToBool {
    param([object]$Value, [bool]$Default = $false)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $Default }
    if ([string]$Value -match '^(?i:true|1|yes)$') { return $true }
    if ([string]$Value -match '^(?i:false|0|no)$') { return $false }
    return $Default
}

function Get-EvidenceWindowCounts {
    param([object[]]$Rows)
    $countsByWindow = @{}
    foreach ($row in $Rows) {
        $key = "$($row.run_id)|$($row.window_id)"
        if (-not $countsByWindow.ContainsKey($key)) {
            $countsByWindow[$key] = [ordered]@{
                wazuh_archive_event_count = 0
                wazuh_alert_event_count = 0
            }
        }

        if ($row.event_source -eq "wazuh_archive") {
            $countsByWindow[$key].wazuh_archive_event_count++
        }
        elseif ($row.event_source -eq "wazuh_alert") {
            $countsByWindow[$key].wazuh_alert_event_count++
        }
    }
    return $countsByWindow
}

function Select-StageRows {
    param([object[]]$Rows, [hashtable]$EvidenceWindowCounts)
    $output = New-Object System.Collections.Generic.List[object]
    foreach ($row in $Rows) {
        $key = "$($row.run_id)|$($row.window_id)"
        $archiveCount = ""
        $alertCount = ""
        if ($EvidenceWindowCounts.ContainsKey($key)) {
            $archiveCount = $EvidenceWindowCounts[$key].wazuh_archive_event_count
            $alertCount = $EvidenceWindowCounts[$key].wazuh_alert_event_count
        }

        $output.Add([PSCustomObject][ordered]@{
            run_id = $row.run_id
            window_id = $row.window_id
            scenario = $row.scenario
            main_label = $row.main_label
            request_count = $row.request_count
            request_rate = $row.request_rate
            observed_source_count = $row.observed_source_count
            same_source_request_ratio = $row.same_source_request_ratio
            status_5xx_count = $row.status_5xx_count
            avg_response_time_ms = $row.avg_response_time_ms
            wazuh_archive_event_count = $archiveCount
            wazuh_alert_event_count = $alertCount
            label_confidence = $row.label_confidence
            label_source = $row.label_source
            stage_label = $row.stage_label
        }) | Out-Null
    }
    return @($output.ToArray())
}

function Select-EvidenceRows {
    param([object[]]$Rows, [switch]$IncludeText)
    $output = New-Object System.Collections.Generic.List[object]
    foreach ($row in $Rows) {
        $ordered = [ordered]@{
            run_id = $row.run_id
            window_id = $row.window_id
            event_source = $row.event_source
            event_type = $row.event_type
            path = $row.path
            source_ip = $row.source_ip
            status_code = $row.status_code
            response_time_ms = $row.response_time_ms
            host = $row.host
            raw_file = $row.raw_file
            label_confidence = $row.label_confidence
            label_source = $row.label_source
            evidence_role = $row.evidence_role
            evidence_score = $row.evidence_score
        }
        if ($IncludeText) {
            $ordered["event_text"] = $row.event_text
        }
        $output.Add([PSCustomObject]$ordered) | Out-Null
    }
    return @($output.ToArray())
}

function Add-GroupCounts {
    param([object[]]$Rows, [string]$PropertyName)
    $counts = [ordered]@{}
    foreach ($group in @($Rows | Group-Object $PropertyName | Sort-Object Name)) {
        $counts[[string]$group.Name] = $group.Count
    }
    return $counts
}

if ([string]::IsNullOrWhiteSpace($BatchId)) { throw "BatchId is required." }

$resolvedInputDir = Resolve-PathInRepo $InputDir
$resolvedOutputDir = Resolve-PathInRepo $OutputDir
$stageInputPath = Join-Path $resolvedInputDir "$BatchId-stage-labels.csv"
$evidenceInputPath = Join-Path $resolvedInputDir "$BatchId-evidence-labels.csv"

if (-not (Test-Path -LiteralPath $stageInputPath -PathType Leaf)) { throw "Stage labels not found: $stageInputPath" }
if (-not (Test-Path -LiteralPath $evidenceInputPath -PathType Leaf)) { throw "Evidence labels not found: $evidenceInputPath" }

New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null

$stageOutputPath = Join-Path $resolvedOutputDir "$BatchId-stage-classification.csv"
$evidenceOutputPath = Join-Path $resolvedOutputDir "$BatchId-evidence-attribution.csv"
$evidenceWithTextPath = Join-Path $resolvedOutputDir "$BatchId-evidence-attribution-with-text.csv"
$dictionaryPath = Join-Path $resolvedOutputDir "$BatchId-explanation-data-dictionary.md"
$summaryPath = Join-Path $resolvedOutputDir "$BatchId-explanation-summary.json"
$outputPaths = @($stageOutputPath, $evidenceOutputPath, $evidenceWithTextPath, $dictionaryPath, $summaryPath)

if (-not $Force) {
    $existing = @($outputPaths | Where-Object { Test-Path -LiteralPath $_ })
    if ($existing.Count -gt 0) {
        throw "Output files already exist. Use -Force to replace files in $resolvedOutputDir only: $($existing -join ', ')"
    }
}

$stageRowsAll = @(Import-Csv -LiteralPath $stageInputPath)
$evidenceRowsAll = @(Import-Csv -LiteralPath $evidenceInputPath)
$stageExcluded = 0
$evidenceExcluded = 0

if ($ExcludeNeedsHumanReview) {
    $stageRows = @($stageRowsAll | Where-Object { -not (Convert-ToBool $_.needs_human_review) })
    $evidenceRows = @($evidenceRowsAll | Where-Object { -not (Convert-ToBool $_.needs_human_review) })
    $stageExcluded = $stageRowsAll.Count - $stageRows.Count
    $evidenceExcluded = $evidenceRowsAll.Count - $evidenceRows.Count
}
else {
    $stageRows = $stageRowsAll
    $evidenceRows = $evidenceRowsAll
}

$evidenceWindowCounts = Get-EvidenceWindowCounts -Rows $evidenceRows
$stageModelRows = Select-StageRows -Rows $stageRows -EvidenceWindowCounts $evidenceWindowCounts
$evidenceModelRows = Select-EvidenceRows -Rows $evidenceRows
$evidenceWithTextRows = Select-EvidenceRows -Rows $evidenceRows -IncludeText

$stageModelRows | Export-Csv -LiteralPath $stageOutputPath -NoTypeInformation -Encoding UTF8
$evidenceModelRows | Export-Csv -LiteralPath $evidenceOutputPath -NoTypeInformation -Encoding UTF8
$evidenceWithTextRows | Export-Csv -LiteralPath $evidenceWithTextPath -NoTypeInformation -Encoding UTF8

$stageColumns = if ($stageModelRows.Count -gt 0) { @($stageModelRows[0].PSObject.Properties.Name) } else { @() }
$evidenceColumns = if ($evidenceModelRows.Count -gt 0) { @($evidenceModelRows[0].PSObject.Properties.Name) } else { @() }
$withTextColumns = if ($evidenceWithTextRows.Count -gt 0) { @($evidenceWithTextRows[0].PSObject.Properties.Name) } else { @() }
$stageColumnLines = ($stageColumns | ForEach-Object { "- ``$_``" }) -join "`r`n"
$evidenceColumnLines = ($evidenceColumns | ForEach-Object { "- ``$_``" }) -join "`r`n"
$withTextColumnLines = ($withTextColumns | ForEach-Object { "- ``$_``" }) -join "`r`n"

@"
# Explanation Data Dictionary - $BatchId

These datasets are prepared from generated explanation labels. They are intended for explanation-model handoff and analysis, not for final model training inside this repository.

Explanation labels are AI-assisted / rule-assisted weak labels unless later human-reviewed.

## Stage Classification Dataset

Path: `$stageOutputPath`

One row = one time window.

Target column:

- `stage_label`

Columns:

$stageColumnLines

## Evidence Attribution Dataset

Path: `$evidenceOutputPath`

One row = one evidence candidate.

Target columns:

- `evidence_role`
- `evidence_score`

Columns:

$evidenceColumnLines

The default evidence-attribution CSV intentionally excludes `event_text` to reduce file size and leakage risk.

## Evidence Attribution With Text

Path: `$evidenceWithTextPath`

This review/traceability export includes full `event_text`:

$withTextColumnLines

Use this file for manual audit and report grounding, not as the default model input.

## Notes

- `run_id`, `window_id`, `host`, and `raw_file` are retained for traceability and review. Downstream strict model baselines may choose to remove them to reduce provenance leakage.
- `scenario` and `main_label` are retained in stage rows as requested context. Downstream experiments should decide whether they are allowed model inputs.
- `source_ip` is retained in evidence rows as requested context. It can be leakage-prone and should be reviewed before model training.
- `wazuh_archive_event_count` and `wazuh_alert_event_count` are derived from the evidence-label candidate rows in this model-ready export. They are not exhaustive raw Wazuh log-volume counts.
- Use `-ExcludeNeedsHumanReview` to omit rows marked for review by the weak-label generator.
"@ | Set-Content -LiteralPath $dictionaryPath -Encoding UTF8

$summary = [ordered]@{
    batch_id = $BatchId
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    parameters = [ordered]@{
        input_dir = $resolvedInputDir
        output_dir = $resolvedOutputDir
        exclude_needs_human_review = [bool]$ExcludeNeedsHumanReview
    }
    inputs = [ordered]@{
        stage_labels_csv = $stageInputPath
        evidence_labels_csv = $evidenceInputPath
    }
    outputs = [ordered]@{
        stage_classification_csv = $stageOutputPath
        evidence_attribution_csv = $evidenceOutputPath
        evidence_attribution_with_text_csv = $evidenceWithTextPath
        explanation_data_dictionary_md = $dictionaryPath
        explanation_summary_json = $summaryPath
    }
    row_counts = [ordered]@{
        stage_input_rows = $stageRowsAll.Count
        stage_output_rows = $stageModelRows.Count
        stage_rows_excluded_needs_human_review = $stageExcluded
        evidence_input_rows = $evidenceRowsAll.Count
        evidence_output_rows = $evidenceModelRows.Count
        evidence_rows_excluded_needs_human_review = $evidenceExcluded
    }
    stage_label_distribution = Add-GroupCounts -Rows $stageModelRows -PropertyName "stage_label"
    stage_main_label_distribution = Add-GroupCounts -Rows $stageModelRows -PropertyName "main_label"
    stage_confidence_distribution = Add-GroupCounts -Rows $stageModelRows -PropertyName "label_confidence"
    evidence_role_distribution = Add-GroupCounts -Rows $evidenceModelRows -PropertyName "evidence_role"
    evidence_score_distribution = Add-GroupCounts -Rows $evidenceModelRows -PropertyName "evidence_score"
    evidence_source_distribution = Add-GroupCounts -Rows $evidenceModelRows -PropertyName "event_source"
    notes = @(
        "Default evidence-attribution CSV excludes event_text to reduce size and leakage risk.",
        "A separate with-text CSV is created for audit and report grounding.",
        "Labels are weak rule-based explanation labels unless manually reviewed.",
        "Stage Wazuh event counts are derived from evidence-label candidate rows, not exhaustive raw Wazuh logs.",
        "Traceability/provenance columns are retained as requested; strict model baselines may remove them later."
    )
}

$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

Write-Host "Model-ready explanation datasets built for $BatchId"
Write-Host "Stage rows: $($stageModelRows.Count) (excluded: $stageExcluded)"
Write-Host "Evidence rows: $($evidenceModelRows.Count) (excluded: $evidenceExcluded)"
Write-Host "Stage classification: $stageOutputPath"
Write-Host "Evidence attribution: $evidenceOutputPath"
Write-Host "Evidence attribution with text: $evidenceWithTextPath"
Write-Host "Data dictionary: $dictionaryPath"
Write-Host "Summary: $summaryPath"
