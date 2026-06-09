<#
.SYNOPSIS
Builds a quality report for generated explanation labels.

.DESCRIPTION
Reads stage/evidence explanation label CSV files, optionally checks for the
model-ready explanation exports, and writes a Markdown and JSON quality report.
The report is descriptive: it does not modify source labels or dataset outputs.
#>

[CmdletBinding()]
param(
    [string]$BatchId = "training-batch-20260607T132426Z",

    [string]$InputDir = "exports\explanation-labels",

    [string]$ModelReadyDir = "exports\model-ready-explanation",

    [string]$OutputDir = "exports\explanation-labels",

    [int]$RandomSeed = 20260607,

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

function Convert-ToIntOrNull {
    param([object]$Value)
    $parsed = 0
    if ([int]::TryParse([string]$Value, [ref]$parsed)) { return $parsed }
    return $null
}

function Get-Percent {
    param([int]$Count, [int]$Total)
    if ($Total -le 0) { return 0 }
    return [math]::Round(($Count / $Total) * 100, 2)
}

function Get-GroupCounts {
    param([object[]]$Rows, [string]$PropertyName)
    $counts = [ordered]@{}
    foreach ($group in @($Rows | Group-Object $PropertyName | Sort-Object Name)) {
        $name = [string]$group.Name
        if ([string]::IsNullOrWhiteSpace($name)) { $name = "(blank)" }
        $counts[$name] = $group.Count
    }
    return $counts
}

function Convert-CountsToMarkdown {
    param([hashtable]$Counts, [string]$NameHeader = "Value")
    if ($Counts.Count -eq 0) { return "_No rows._" }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("| $NameHeader | Count |") | Out-Null
    $lines.Add("|---|---:|") | Out-Null
    foreach ($key in $Counts.Keys) {
        $safeKey = [string]$key
        $lines.Add("| $safeKey | $($Counts[$key]) |") | Out-Null
    }
    return ($lines -join "`r`n")
}

function Select-StageSampleFields {
    param([object[]]$Rows)
    return @($Rows | Select-Object run_id, window_id, scenario, main_label, request_count, request_rate, observed_source_count, status_5xx_count, avg_response_time_ms, stage_label, label_confidence, needs_human_review)
}

function Select-EvidenceSampleFields {
    param([object[]]$Rows)
    return @($Rows | Select-Object run_id, window_id, event_source, event_type, path, source_ip, status_code, response_time_ms, evidence_role, evidence_score, label_confidence, needs_human_review)
}

function Convert-SampleToMarkdown {
    param([object[]]$Rows, [string[]]$Columns)
    if ($Rows.Count -eq 0) { return "_No matching rows._" }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("| $($Columns -join ' | ') |") | Out-Null
    $lines.Add("|$((@('---') * $Columns.Count) -join '|')|") | Out-Null

    foreach ($row in $Rows) {
        $values = foreach ($column in $Columns) {
            $value = [string]$row.$column
            $value = $value.Replace("|", "\|").Replace("`r", " ").Replace("`n", " ")
            if ($value.Length -gt 120) { $value = $value.Substring(0, 117) + "..." }
            $value
        }
        $lines.Add("| $($values -join ' | ') |") | Out-Null
    }
    return ($lines -join "`r`n")
}

function Test-ExplicitDegradationEvidence {
    param([object]$Row)
    $statusCode = Convert-ToIntOrNull $Row.status_code
    if ($null -ne $statusCode -and $statusCode -ge 500) { return $true }

    $text = "$($Row.event_type) $($Row.path) $($Row.event_text) $($Row.evidence_role)".ToLowerInvariant()
    $patterns = @(
        "failed health check",
        "health_check_failure",
        "health check failed",
        "timeout",
        "timed out",
        "service unavailable",
        "connection refused",
        "nginx error",
        "upstream timed out",
        "upstream prematurely closed",
        "error_evidence"
    )
    foreach ($pattern in $patterns) {
        if ($text.Contains($pattern)) { return $true }
    }
    return $false
}

function Select-StableRandomSample {
    param([object[]]$Rows, [int]$Count, [int]$Seed)
    if ($Rows.Count -le $Count) { return @($Rows) }
    Get-Random -SetSeed $Seed | Out-Null
    return @($Rows | Sort-Object { Get-Random } | Select-Object -First $Count)
}

if ([string]::IsNullOrWhiteSpace($BatchId)) { throw "BatchId is required." }

$resolvedInputDir = Resolve-PathInRepo $InputDir
$resolvedModelReadyDir = Resolve-PathInRepo $ModelReadyDir
$resolvedOutputDir = Resolve-PathInRepo $OutputDir

$stageInputPath = Join-Path $resolvedInputDir "$BatchId-stage-labels.csv"
$evidenceInputPath = Join-Path $resolvedInputDir "$BatchId-evidence-labels.csv"
$modelStagePath = Join-Path $resolvedModelReadyDir "$BatchId-stage-classification.csv"
$modelEvidencePath = Join-Path $resolvedModelReadyDir "$BatchId-evidence-attribution.csv"

if (-not (Test-Path -LiteralPath $stageInputPath -PathType Leaf)) { throw "Stage labels not found: $stageInputPath" }
if (-not (Test-Path -LiteralPath $evidenceInputPath -PathType Leaf)) { throw "Evidence labels not found: $evidenceInputPath" }

New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null

$markdownPath = Join-Path $resolvedOutputDir "$BatchId-EXPLANATION_LABEL_QUALITY_REPORT.md"
$jsonPath = Join-Path $resolvedOutputDir "$BatchId-explanation-label-quality-report.json"

if (-not $Force) {
    $existing = @($markdownPath, $jsonPath | Where-Object { Test-Path -LiteralPath $_ })
    if ($existing.Count -gt 0) {
        throw "Output files already exist. Use -Force to replace report files only: $($existing -join ', ')"
    }
}

$stageRows = @(Import-Csv -LiteralPath $stageInputPath)
$evidenceRows = @(Import-Csv -LiteralPath $evidenceInputPath)
$modelStageExists = Test-Path -LiteralPath $modelStagePath -PathType Leaf
$modelEvidenceExists = Test-Path -LiteralPath $modelEvidencePath -PathType Leaf
$modelStageRows = if ($modelStageExists) { @(Import-Csv -LiteralPath $modelStagePath) } else { @() }
$modelEvidenceRows = if ($modelEvidenceExists) { @(Import-Csv -LiteralPath $modelEvidencePath) } else { @() }

$totalStageRows = $stageRows.Count
$totalEvidenceRows = $evidenceRows.Count
$stageReviewRows = @($stageRows | Where-Object { Convert-ToBool $_.needs_human_review })
$evidenceReviewRows = @($evidenceRows | Where-Object { Convert-ToBool $_.needs_human_review })
$reviewCount = $stageReviewRows.Count + $evidenceReviewRows.Count
$totalLabelRows = $totalStageRows + $totalEvidenceRows
$reviewPercent = Get-Percent -Count $reviewCount -Total $totalLabelRows

$serviceDegradationRows = @($stageRows | Where-Object { $_.stage_label -eq "service_degradation" })
$serviceDegradationWindows = @{}
foreach ($row in $serviceDegradationRows) {
    $serviceDegradationWindows["$($row.run_id)|$($row.window_id)"] = $true
}
$serviceDegradationEvidenceRows = @(
    $evidenceRows | Where-Object {
        $serviceDegradationWindows.ContainsKey("$($_.run_id)|$($_.window_id)") -and (Test-ExplicitDegradationEvidence $_)
    }
)
$serviceDegradationHasExplicitEvidence = ($serviceDegradationRows.Count -eq 0) -or ($serviceDegradationEvidenceRows.Count -gt 0)

$irrelevantWazuhAlerts = @($evidenceRows | Where-Object { $_.event_source -eq "wazuh_alert" -and $_.evidence_role -eq "irrelevant" })
$wazuhConfirmations = @($evidenceRows | Where-Object { $_.evidence_role -eq "wazuh_confirmation" })
$strongEvidenceRows = @($evidenceRows | Where-Object { $_.evidence_score -eq "3" })
$lowConfidenceStageRows = @($stageRows | Where-Object { $_.label_confidence -eq "low" })
$lowConfidenceEvidenceRows = @($evidenceRows | Where-Object { $_.label_confidence -eq "low" })

$labelSourceRows = @()
$labelSourceRows += $stageRows | Select-Object label_source
$labelSourceRows += $evidenceRows | Select-Object label_source
$labelConfidenceRows = @()
$labelConfidenceRows += $stageRows | Select-Object label_confidence
$labelConfidenceRows += $evidenceRows | Select-Object label_confidence

$manualReview = [ordered]@{
    service_degradation_stage_rows = Select-StageSampleFields -Rows $serviceDegradationRows
    low_confidence_stage_rows = Select-StageSampleFields -Rows $lowConfidenceStageRows
    low_confidence_evidence_rows = Select-EvidenceSampleFields -Rows $lowConfidenceEvidenceRows
    random_score_3_evidence_rows = Select-EvidenceSampleFields -Rows (Select-StableRandomSample -Rows $strongEvidenceRows -Count 20 -Seed ($RandomSeed + 3))
    random_irrelevant_wazuh_alert_rows = Select-EvidenceSampleFields -Rows (Select-StableRandomSample -Rows $irrelevantWazuhAlerts -Count 20 -Seed ($RandomSeed + 7))
    benign_stage_examples = Select-StageSampleFields -Rows (Select-StableRandomSample -Rows @($stageRows | Where-Object { $_.scenario -eq "Benign" }) -Count 5 -Seed ($RandomSeed + 11))
    lightdos_stage_examples = Select-StageSampleFields -Rows (Select-StableRandomSample -Rows @($stageRows | Where-Object { $_.scenario -eq "LightDos" }) -Count 5 -Seed ($RandomSeed + 13))
    attackerhostlightdos_stage_examples = Select-StageSampleFields -Rows (Select-StableRandomSample -Rows @($stageRows | Where-Object { $_.scenario -eq "AttackerHostLightDos" }) -Count 5 -Seed ($RandomSeed + 17))
}

$report = [ordered]@{
    batch_id = $BatchId
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    inputs = [ordered]@{
        stage_labels_csv = $stageInputPath
        evidence_labels_csv = $evidenceInputPath
        model_ready_stage_classification_csv = if ($modelStageExists) { $modelStagePath } else { $null }
        model_ready_evidence_attribution_csv = if ($modelEvidenceExists) { $modelEvidencePath } else { $null }
    }
    outputs = [ordered]@{
        markdown_report = $markdownPath
        json_report = $jsonPath
    }
    totals = [ordered]@{
        stage_rows = $totalStageRows
        evidence_rows = $totalEvidenceRows
        label_rows = $totalLabelRows
        model_ready_stage_rows = if ($modelStageExists) { $modelStageRows.Count } else { $null }
        model_ready_evidence_rows = if ($modelEvidenceExists) { $modelEvidenceRows.Count } else { $null }
    }
    distributions = [ordered]@{
        stage_label = Get-GroupCounts -Rows $stageRows -PropertyName "stage_label"
        evidence_role = Get-GroupCounts -Rows $evidenceRows -PropertyName "evidence_role"
        evidence_score = Get-GroupCounts -Rows $evidenceRows -PropertyName "evidence_score"
        label_source_all_rows = Get-GroupCounts -Rows $labelSourceRows -PropertyName "label_source"
        label_source_stage_rows = Get-GroupCounts -Rows $stageRows -PropertyName "label_source"
        label_source_evidence_rows = Get-GroupCounts -Rows $evidenceRows -PropertyName "label_source"
        label_confidence_all_rows = Get-GroupCounts -Rows $labelConfidenceRows -PropertyName "label_confidence"
        label_confidence_stage_rows = Get-GroupCounts -Rows $stageRows -PropertyName "label_confidence"
        label_confidence_evidence_rows = Get-GroupCounts -Rows $evidenceRows -PropertyName "label_confidence"
    }
    quality_checks = [ordered]@{
        needs_human_review_count = $reviewCount
        needs_human_review_percentage = $reviewPercent
        stage_rows_needing_human_review = $stageReviewRows.Count
        evidence_rows_needing_human_review = $evidenceReviewRows.Count
        service_degradation_stage_count = $serviceDegradationRows.Count
        service_degradation_explicit_evidence_count = $serviceDegradationEvidenceRows.Count
        service_degradation_has_explicit_evidence = $serviceDegradationHasExplicitEvidence
        irrelevant_wazuh_alert_count = $irrelevantWazuhAlerts.Count
        wazuh_confirmation_evidence_count = $wazuhConfirmations.Count
        strong_score_3_evidence_count = $strongEvidenceRows.Count
    }
    recommended_manual_review_sample = $manualReview
    known_limitations = @(
        "Explanation labels are rule-assisted weak labels, not manually verified ground truth.",
        "The dataset is controlled lab-generated traffic, mostly single-source DoS/service-stress rather than true distributed DDoS.",
        "No packet capture is used; evidence is server-side logs and Wazuh-linked logs/alerts.",
        "The report can confirm label consistency heuristics, but it cannot prove semantic correctness without manual log review.",
        "Model-ready exports intentionally omit full event_text by default to reduce leakage and size."
    )
}

$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$stageDistributionMd = Convert-CountsToMarkdown -Counts $report.distributions.stage_label -NameHeader "Stage label"
$evidenceRoleMd = Convert-CountsToMarkdown -Counts $report.distributions.evidence_role -NameHeader "Evidence role"
$evidenceScoreMd = Convert-CountsToMarkdown -Counts $report.distributions.evidence_score -NameHeader "Evidence score"
$labelSourceMd = Convert-CountsToMarkdown -Counts $report.distributions.label_source_all_rows -NameHeader "Label source"
$labelConfidenceMd = Convert-CountsToMarkdown -Counts $report.distributions.label_confidence_all_rows -NameHeader "Label confidence"
$limitationsMd = ($report.known_limitations | ForEach-Object { "- $_" }) -join "`r`n"

$score3Columns = @("run_id", "window_id", "event_source", "event_type", "path", "source_ip", "status_code", "response_time_ms", "evidence_role", "evidence_score", "label_confidence")
$stageSampleColumns = @("run_id", "window_id", "scenario", "main_label", "request_count", "request_rate", "observed_source_count", "status_5xx_count", "avg_response_time_ms", "stage_label", "label_confidence")
$evidenceSampleColumns = @("run_id", "window_id", "event_source", "event_type", "path", "source_ip", "status_code", "response_time_ms", "evidence_role", "evidence_score", "label_confidence")
$generatedUtc = $report.generated_at_utc
$modelStageSummary = if ($modelStageExists) { [string]$modelStageRows.Count } else { "not found" }
$modelEvidenceSummary = if ($modelEvidenceExists) { [string]$modelEvidenceRows.Count } else { "not found" }
$serviceDegradationCount = $serviceDegradationRows.Count
$serviceDegradationEvidenceCount = $serviceDegradationEvidenceRows.Count
$irrelevantWazuhAlertCount = $irrelevantWazuhAlerts.Count
$wazuhConfirmationCount = $wazuhConfirmations.Count
$strongEvidenceCount = $strongEvidenceRows.Count

@"
# Explanation Label Quality Report - $BatchId

Generated UTC: $generatedUtc

## Summary

- Batch ID: $BatchId
- Stage label rows: $totalStageRows
- Evidence label rows: $totalEvidenceRows
- Total label rows: $totalLabelRows
- Model-ready stage rows present: $modelStageSummary
- Model-ready evidence rows present: $modelEvidenceSummary
- Rows needing human review: $reviewCount ($reviewPercent%)
- Service degradation stage rows: $serviceDegradationCount
- Service degradation explicit evidence rows: $serviceDegradationEvidenceCount
- Service degradation explicit-evidence check passed: $serviceDegradationHasExplicitEvidence
- Irrelevant Wazuh alert rows: $irrelevantWazuhAlertCount
- Wazuh confirmation evidence rows: $wazuhConfirmationCount
- Strong evidence rows with score 3: $strongEvidenceCount

## Stage Label Distribution

$stageDistributionMd

## Evidence Role Distribution

$evidenceRoleMd

## Evidence Score Distribution

$evidenceScoreMd

## Label Source Distribution

$labelSourceMd

## Label Confidence Distribution

$labelConfidenceMd

## Manual Review Sample

### Service Degradation Rows

$(Convert-SampleToMarkdown -Rows $manualReview.service_degradation_stage_rows -Columns $stageSampleColumns)

### Low-Confidence Stage Rows

$(Convert-SampleToMarkdown -Rows $manualReview.low_confidence_stage_rows -Columns $stageSampleColumns)

### Low-Confidence Evidence Rows

$(Convert-SampleToMarkdown -Rows $manualReview.low_confidence_evidence_rows -Columns $evidenceSampleColumns)

### Random Score-3 Evidence Rows

$(Convert-SampleToMarkdown -Rows $manualReview.random_score_3_evidence_rows -Columns $score3Columns)

### Random Irrelevant Wazuh Alert Rows

$(Convert-SampleToMarkdown -Rows $manualReview.random_irrelevant_wazuh_alert_rows -Columns $evidenceSampleColumns)

### Benign Stage Examples

$(Convert-SampleToMarkdown -Rows $manualReview.benign_stage_examples -Columns $stageSampleColumns)

### LightDos Stage Examples

$(Convert-SampleToMarkdown -Rows $manualReview.lightdos_stage_examples -Columns $stageSampleColumns)

### AttackerHostLightDos Stage Examples

$(Convert-SampleToMarkdown -Rows $manualReview.attackerhostlightdos_stage_examples -Columns $stageSampleColumns)

## Known Limitations

$limitationsMd
"@ | Set-Content -LiteralPath $markdownPath -Encoding UTF8

Write-Host "Explanation label quality report built for $BatchId"
Write-Host "Stage rows: $totalStageRows"
Write-Host "Evidence rows: $totalEvidenceRows"
Write-Host "Needs human review: $reviewCount ($reviewPercent%)"
Write-Host "Service degradation rows: $($serviceDegradationRows.Count); explicit evidence rows: $($serviceDegradationEvidenceRows.Count)"
Write-Host "Irrelevant Wazuh alerts: $($irrelevantWazuhAlerts.Count)"
Write-Host "Wazuh confirmations: $($wazuhConfirmations.Count)"
Write-Host "Strong score-3 evidence rows: $($strongEvidenceRows.Count)"
Write-Host "Markdown report: $markdownPath"
Write-Host "JSON report: $jsonPath"
