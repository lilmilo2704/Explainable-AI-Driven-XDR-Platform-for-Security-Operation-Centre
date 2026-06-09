<#
.SYNOPSIS
Creates human-review candidate files for stage labels and evidence labels.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BatchManifestPath,

    [string]$WindowedDatasetPath,

    [string]$VerifiedRunsRoot = "exports\verified-runs",

    [string]$OutputDir = "exports\labelling-candidates",

    [ValidateRange(1, 200)]
    [int]$MaxEvidencePerWindow = 30,

    [ValidateRange(1, 3600)]
    [int]$WindowSeconds = 5
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Path (Split-Path -Path $MyInvocation.MyCommand.Path -Parent) -Parent

function Resolve-PathInRepo {
    param([string]$Path)
    if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
    return [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
}

function Get-Value {
    param([object]$Object, [string[]]$Names, [object]$Default = "")
    if ($null -eq $Object) { return $Default }
    foreach ($name in $Names) {
        $prop = $Object.PSObject.Properties[$name]
        if ($prop -and $null -ne $prop.Value -and -not [string]::IsNullOrWhiteSpace([string]$prop.Value)) { return $prop.Value }
    }
    return $Default
}

function Convert-ToUtc {
    param([object]$Value)
    try { return ([DateTimeOffset]::Parse([string]$Value)).UtcDateTime } catch { return $null }
}

function Get-EvidenceRole {
    param([object]$Candidate)
    $source = [string]$Candidate.source
    $status = [int]$Candidate.status_code
    $latency = 0.0
    [double]::TryParse([string]$Candidate.response_time_ms, [ref]$latency) | Out-Null
    if ($status -ge 500) { return "error_evidence" }
    if ($status -ge 400) { return "error_evidence" }
    if ($latency -ge 1000) { return "latency_evidence" }
    if ($source -eq "wazuh_alert") { return "wazuh_confirmation" }
    if ($Candidate.path -eq "/health" -and $status -ge 400) { return "health_check_failure" }
    if ($Candidate.window_id -match "window-0000") { return "representative_burst_request" }
    return "baseline_sample"
}

function Read-WebCandidates {
    param([string]$Path, [datetime]$StartUtc, [datetime]$EndUtc)
    $rows = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $lineNo = 0
    foreach ($line in (Get-Content -LiteralPath $Path)) {
        $lineNo++
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $event = $line | ConvertFrom-Json -ErrorAction Stop
            $ts = Convert-ToUtc (Get-Value -Object $event -Names @("timestamp", "@timestamp"))
            if (-not $ts -or $ts -lt $StartUtc -or $ts -ge $EndUtc) { continue }
            $rows.Add([PSCustomObject]@{
                event_timestamp_utc = $ts.ToString("o")
                source = "webapp"
                host = "web-server"
                agent_name = ""
                location = "webapp-slice.log:$lineNo"
                event_type = [string](Get-Value -Object $event -Names @("event_type"))
                method = [string](Get-Value -Object $event -Names @("method"))
                path = [string](Get-Value -Object $event -Names @("path", "endpoint"))
                query = [string](Get-Value -Object $event -Names @("query"))
                status_code = [string](Get-Value -Object $event -Names @("status_code"))
                source_ip = [string](Get-Value -Object $event -Names @("source_ip"))
                response_time_ms = [string](Get-Value -Object $event -Names @("response_time_ms"))
                request_duration_ms = [string](Get-Value -Object $event -Names @("request_duration_ms"))
                wazuh_rule_id = ""
                wazuh_rule_level = ""
                wazuh_decoder = ""
                event_text = $line
            }) | Out-Null
        }
        catch {
        }
    }
    return @($rows.ToArray())
}

function Read-NginxCandidates {
    param([string]$Path, [datetime]$StartUtc, [datetime]$EndUtc)
    $rows = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $lineNo = 0
    foreach ($line in (Get-Content -LiteralPath $Path)) {
        $lineNo++
        $match = [regex]::Match([string]$line, '^(?<source_ip>\S+)\s+.*?\[(?<timestamp>[^\]]+)\]\s+"(?<method>[A-Z]+)\s+(?<path>\S+)[^"]*"\s+(?<status>\d{3})')
        if (-not $match.Success) { continue }
        try {
            $ts = [DateTimeOffset]::ParseExact($match.Groups["timestamp"].Value, "dd/MMM/yyyy:HH:mm:ss zzz", [System.Globalization.CultureInfo]::InvariantCulture).UtcDateTime
            if ($ts -lt $StartUtc -or $ts -ge $EndUtc) { continue }
            $rows.Add([PSCustomObject]@{
                event_timestamp_utc = $ts.ToString("o")
                source = "nginx"
                host = "web-server"
                agent_name = ""
                location = "nginx-access-slice.log:$lineNo"
                event_type = "nginx_access"
                method = $match.Groups["method"].Value
                path = $match.Groups["path"].Value
                query = ""
                status_code = $match.Groups["status"].Value
                source_ip = $match.Groups["source_ip"].Value
                response_time_ms = ""
                request_duration_ms = ""
                wazuh_rule_id = ""
                wazuh_rule_level = ""
                wazuh_decoder = ""
                event_text = $line
            }) | Out-Null
        }
        catch {
        }
    }
    return @($rows.ToArray())
}

function Read-WazuhCandidates {
    param([string]$Path, [string]$Source, [datetime]$StartUtc, [datetime]$EndUtc)
    $rows = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $lineNo = 0
    foreach ($line in (Get-Content -LiteralPath $Path)) {
        $lineNo++
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $event = $line | ConvertFrom-Json -ErrorAction Stop
            $ts = Convert-ToUtc (Get-Value -Object $event -Names @("timestamp", "@timestamp"))
            if (-not $ts -or $ts -lt $StartUtc -or $ts -ge $EndUtc) { continue }
            $rows.Add([PSCustomObject]@{
                event_timestamp_utc = $ts.ToString("o")
                source = $Source
                host = [string](Get-Value -Object $event.agent -Names @("name", "id"))
                agent_name = [string](Get-Value -Object $event.agent -Names @("name"))
                location = [string](Get-Value -Object $event -Names @("location") -Default "$Source`:$lineNo")
                event_type = "wazuh_event"
                method = ""
                path = ""
                query = ""
                status_code = ""
                source_ip = ""
                response_time_ms = ""
                request_duration_ms = ""
                wazuh_rule_id = [string](Get-Value -Object $event.rule -Names @("id"))
                wazuh_rule_level = [string](Get-Value -Object $event.rule -Names @("level"))
                wazuh_decoder = [string](Get-Value -Object $event.decoder -Names @("name"))
                event_text = $line
            }) | Out-Null
        }
        catch {
        }
    }
    return @($rows.ToArray())
}

$resolvedBatch = Resolve-PathInRepo $BatchManifestPath
$batch = Get-Content -Raw -LiteralPath $resolvedBatch | ConvertFrom-Json
$batchId = [string]$batch.batch_id
$resolvedRunsRoot = Resolve-PathInRepo $VerifiedRunsRoot
$resolvedOutputDir = Resolve-PathInRepo $OutputDir
New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null

if ([string]::IsNullOrWhiteSpace($WindowedDatasetPath)) {
    $candidate = Join-Path (Resolve-PathInRepo "exports\windowed-datasets") "$batchId-windows.csv"
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $WindowedDatasetPath = $candidate
    }
}

if ([string]::IsNullOrWhiteSpace($WindowedDatasetPath) -or -not (Test-Path -LiteralPath (Resolve-PathInRepo $WindowedDatasetPath) -PathType Leaf)) {
    throw "Windowed dataset not found. Run scripts\build-windowed-dataset.ps1 first or pass -WindowedDatasetPath."
}

$windows = @(Import-Csv -LiteralPath (Resolve-PathInRepo $WindowedDatasetPath))
$stagePath = Join-Path $resolvedOutputDir "$batchId-stage-label-candidates.csv"
$evidencePath = Join-Path $resolvedOutputDir "$batchId-evidence-label-candidates.csv"
$guidePath = Join-Path $resolvedOutputDir "$batchId-labelling-guide.md"

$stageRows = New-Object System.Collections.Generic.List[object]
$evidenceRows = New-Object System.Collections.Generic.List[object]

foreach ($window in $windows) {
    $stageRows.Add([PSCustomObject][ordered]@{
        batch_id = $batchId
        run_id = $window.run_id
        scenario = $window.scenario
        scenario_variant = $window.scenario_variant
        main_label = $window.main_label
        sublabel = $window.sublabel
        intensity = $window.intensity
        window_id = $window.window_id
        window_start_utc = $window.window_start_utc
        window_end_utc = $window.window_end_utc
        request_count = $window.request_count
        request_rate_per_second = $window.request_rate_per_second
        unique_source_ip_count = $window.unique_source_ip_count
        top_source_ip_ratio = $window.top_source_ip_ratio
        status_5xx_count = $window.status_5xx_count
        error_rate = $window.error_rate
        avg_response_time_ms = $window.avg_response_time_ms
        max_response_time_ms = $window.max_response_time_ms
        health_check_failed_count = $window.health_check_failed_count
        suggested_stage_label = $window.stage_label
        manual_stage_label = ""
        manual_label_confidence = ""
        notes = ""
    }) | Out-Null

    $runDir = Join-Path $resolvedRunsRoot ([string]$window.run_id -replace '[^A-Za-z0-9._-]', '_')
    $start = Convert-ToUtc $window.window_start_utc
    $end = Convert-ToUtc $window.window_end_utc
    if (-not $start -or -not $end) { continue }

    $candidates = @()
    $candidates += @(Read-WebCandidates -Path (Join-Path $runDir "webapp-slice.log") -StartUtc $start -EndUtc $end)
    $candidates += @(Read-NginxCandidates -Path (Join-Path $runDir "nginx-access-slice.log") -StartUtc $start -EndUtc $end)
    $candidates += @(Read-WazuhCandidates -Path (Join-Path $runDir "wazuh-archives-slice.json") -Source "wazuh_archive" -StartUtc $start -EndUtc $end)
    $candidates += @(Read-WazuhCandidates -Path (Join-Path $runDir "wazuh-alerts-slice.json") -Source "wazuh_alert" -StartUtc $start -EndUtc $end)

    $selected = @($candidates |
        Sort-Object @{ Expression = { if ([int]($_.status_code -as [int]) -ge 400) { 0 } elseif ($_.source -eq "wazuh_alert") { 1 } else { 2 } } }, event_timestamp_utc |
        Select-Object -First $MaxEvidencePerWindow)

    $eventIndex = 0
    foreach ($candidate in $selected) {
        $eventIndex++
        $candidate | Add-Member -NotePropertyName window_id -NotePropertyValue $window.window_id -Force
        $role = Get-EvidenceRole -Candidate $candidate
        $evidenceRows.Add([PSCustomObject][ordered]@{
            batch_id = $batchId
            run_id = $window.run_id
            window_id = $window.window_id
            event_id = "$($window.window_id)-event-$('{0:D3}' -f $eventIndex)"
            event_timestamp_utc = $candidate.event_timestamp_utc
            source = $candidate.source
            host = $candidate.host
            agent_name = $candidate.agent_name
            location = $candidate.location
            event_type = $candidate.event_type
            method = $candidate.method
            path = $candidate.path
            query = $candidate.query
            status_code = $candidate.status_code
            source_ip = $candidate.source_ip
            response_time_ms = $candidate.response_time_ms
            request_duration_ms = $candidate.request_duration_ms
            wazuh_rule_id = $candidate.wazuh_rule_id
            wazuh_rule_level = $candidate.wazuh_rule_level
            wazuh_decoder = $candidate.wazuh_decoder
            event_text = $candidate.event_text
            suggested_evidence_role = $role
            manual_evidence_score = ""
            manual_evidence_role = ""
            include_in_graph = ""
            notes = ""
        }) | Out-Null
    }
}

$stageRows.ToArray() | Export-Csv -LiteralPath $stagePath -NoTypeInformation -Encoding UTF8
$evidenceRows.ToArray() | Export-Csv -LiteralPath $evidencePath -NoTypeInformation -Encoding UTF8

@"
# Labelling Guide - $batchId

Stage labels are candidates only. Final training stage labels require manual review.

Evidence score:
- 0 = irrelevant
- 1 = weak supporting evidence
- 2 = useful evidence
- 3 = strong evidence / should appear on graph

Evidence roles:
- baseline_sample
- representative_burst_request
- source_concentration_evidence
- distributed_source_evidence
- sustained_pressure_evidence
- latency_evidence
- error_evidence
- health_check_failure
- wazuh_confirmation
- service_recovery_evidence
- irrelevant

Do not use Wazuh alerts as ground truth labels. Use controlled run metadata for incident labels and manual review for stage/evidence labels.
"@ | Set-Content -LiteralPath $guidePath -Encoding UTF8

Write-Host "Stage candidates: $stagePath"
Write-Host "Evidence candidates: $evidencePath"
Write-Host "Guide: $guidePath"
