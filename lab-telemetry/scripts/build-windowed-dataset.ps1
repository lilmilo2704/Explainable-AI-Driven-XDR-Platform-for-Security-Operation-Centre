<#
.SYNOPSIS
Builds a time-window-level dataset from verified run folders.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BatchManifestPath,

    [string]$VerifiedRunsRoot = "exports\verified-runs",

    [string]$OutputDir = "exports\windowed-datasets",

    [ValidateRange(1, 3600)]
    [int]$WindowSeconds = 5,

    [ValidateRange(1, 3600)]
    [int]$StepSeconds = 5,

    [switch]$IncludeWazuh,

    [switch]$IncludeRawEvidenceRefs
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Path (Split-Path -Path $MyInvocation.MyCommand.Path -Parent) -Parent

function Resolve-PathInRepo {
    param([string]$Path)
    if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
    return [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
}

function Get-Value {
    param([object]$Object, [string[]]$Names, [object]$Default = $null)
    if ($null -eq $Object) { return $Default }
    foreach ($name in $Names) {
        $prop = $Object.PSObject.Properties[$name]
        if ($prop -and $null -ne $prop.Value -and -not [string]::IsNullOrWhiteSpace([string]$prop.Value)) {
            return $prop.Value
        }
    }
    return $Default
}

function Convert-ToUtc {
    param([object]$Value)
    try { return ([DateTimeOffset]::Parse([string]$Value)).UtcDateTime } catch { return $null }
}

function Convert-ToDoubleOrNull {
    param([object]$Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    $parsed = 0.0
    if ([double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) { return $parsed }
    return $null
}

function Get-Percentile {
    param([double[]]$Values, [double]$Percentile = 0.95)
    $vals = @($Values | Where-Object { $null -ne $_ } | Sort-Object)
    if ($vals.Count -eq 0) { return 0 }
    $index = [Math]::Ceiling($Percentile * $vals.Count) - 1
    $index = [Math]::Max(0, [Math]::Min($vals.Count - 1, $index))
    return [Math]::Round([double]$vals[$index], 3)
}

function Add-StatusBucket {
    param([int]$StatusCode, [hashtable]$Buckets)
    if ($StatusCode -ge 200 -and $StatusCode -lt 300) { $Buckets["2xx"]++ }
    elseif ($StatusCode -ge 300 -and $StatusCode -lt 400) { $Buckets["3xx"]++ }
    elseif ($StatusCode -ge 400 -and $StatusCode -lt 500) { $Buckets["4xx"]++; $Buckets["error"]++ }
    elseif ($StatusCode -ge 500 -and $StatusCode -lt 600) { $Buckets["5xx"]++; $Buckets["error"]++ }
}

function Read-WebEvents {
    param([string]$Path)
    $events = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $lineNo = 0
    foreach ($line in (Get-Content -LiteralPath $Path)) {
        $lineNo++
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $event = $line | ConvertFrom-Json -ErrorAction Stop
            $ts = Convert-ToUtc (Get-Value -Object $event -Names @("timestamp", "@timestamp", "time"))
            if ($ts) {
                $events.Add([PSCustomObject]@{ TimestampUtc = $ts; Event = $event; Raw = $line; Source = "webapp"; Line = $lineNo }) | Out-Null
            }
        }
        catch {
        }
    }
    return @($events.ToArray())
}

function Read-NginxEvents {
    param([string]$Path)
    $events = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $lineNo = 0
    foreach ($line in (Get-Content -LiteralPath $Path)) {
        $lineNo++
        $match = [regex]::Match([string]$line, '^(?<source_ip>\S+)\s+.*?\[(?<timestamp>[^\]]+)\]\s+"(?<method>[A-Z]+)\s+(?<target>\S+)[^"]*"\s+(?<status>\d{3})')
        if (-not $match.Success) { continue }
        try {
            $ts = [DateTimeOffset]::ParseExact($match.Groups["timestamp"].Value, "dd/MMM/yyyy:HH:mm:ss zzz", [System.Globalization.CultureInfo]::InvariantCulture).UtcDateTime
            $events.Add([PSCustomObject]@{
                TimestampUtc = $ts
                Source = "nginx"
                SourceIp = $match.Groups["source_ip"].Value
                Method = $match.Groups["method"].Value
                Path = $match.Groups["target"].Value
                StatusCode = [int]$match.Groups["status"].Value
                Raw = $line
                Line = $lineNo
            }) | Out-Null
        }
        catch {
        }
    }
    return @($events.ToArray())
}

function Read-WazuhEvents {
    param([string]$Path, [string]$Source)
    $events = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $lineNo = 0
    foreach ($line in (Get-Content -LiteralPath $Path)) {
        $lineNo++
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $event = $line | ConvertFrom-Json -ErrorAction Stop
            $ts = Convert-ToUtc (Get-Value -Object $event -Names @("timestamp", "@timestamp"))
            if ($ts) {
                $events.Add([PSCustomObject]@{ TimestampUtc = $ts; Event = $event; Source = $Source; Raw = $line; Line = $lineNo }) | Out-Null
            }
        }
        catch {
        }
    }
    return @($events.ToArray())
}

function Get-SourceSummary {
    param([string[]]$Sources)
    $valid = @($Sources | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($valid.Count -eq 0) { return [PSCustomObject]@{ Count = 0; Dominant = ""; Ratio = 0 } }
    $groups = @($valid | Group-Object | Sort-Object Count -Descending)
    return [PSCustomObject]@{ Count = $groups.Count; Dominant = [string]$groups[0].Name; Ratio = [Math]::Round([double]$groups[0].Count / [double]$valid.Count, 3) }
}

function Get-StageLabel {
    param(
        [string]$Scenario,
        [string]$Variant,
        [int]$WindowIndex,
        [double]$Rate,
        [double]$TopSourceRatio,
        [int]$ErrorCount,
        [double]$MaxLatency,
        [int]$HealthFailed
    )

    if ($Scenario -eq "Benign") {
        if ($Variant -match "heavy|repeated|burst|mixed") { return "benign_high_activity" }
        return "baseline"
    }
    if ($ErrorCount -gt 0 -or $HealthFailed -gt 0) { return "service_degradation" }
    if ($MaxLatency -ge 1000) { return "service_stress" }
    if ($WindowIndex -eq 0 -and $Rate -ge 2) { return "burst_onset" }
    if ($Rate -ge 2 -and $TopSourceRatio -ge 0.8) { return "sustained_pressure" }
    if ($Rate -gt 0) { return "sustained_pressure" }
    return "unknown"
}

$resolvedBatch = Resolve-PathInRepo $BatchManifestPath
$resolvedRunsRoot = Resolve-PathInRepo $VerifiedRunsRoot
$resolvedOutputDir = Resolve-PathInRepo $OutputDir
New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null

$batch = Get-Content -Raw -LiteralPath $resolvedBatch | ConvertFrom-Json
$batchId = [string]$batch.batch_id
$csvPath = Join-Path $resolvedOutputDir "$batchId-windows.csv"
$jsonPath = Join-Path $resolvedOutputDir "$batchId-windows.json"
$summaryPath = Join-Path $resolvedOutputDir "$batchId-window-build-summary.json"

Write-Host "Building windowed dataset for $batchId"

$rows = New-Object System.Collections.Generic.List[object]
$warnings = New-Object System.Collections.Generic.List[string]

foreach ($run in @($batch.runs)) {
    $runId = [string](Get-Value -Object $run -Names @("run_id"))
    if ([string]::IsNullOrWhiteSpace($runId)) { continue }
    $runDir = Join-Path $resolvedRunsRoot ($runId -replace '[^A-Za-z0-9._-]', '_')
    $metadataPath = Join-Path $runDir "metadata.json"
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
        $warnings.Add("Missing metadata for $runId") | Out-Null
        continue
    }

    $metadata = Get-Content -Raw -LiteralPath $metadataPath | ConvertFrom-Json
    $start = Convert-ToUtc (Get-Value -Object $metadata -Names @("start_time_utc"))
    $end = Convert-ToUtc (Get-Value -Object $metadata -Names @("end_time_utc"))
    if (-not $start -or -not $end -or $end -le $start) {
        $warnings.Add("Invalid run window for $runId") | Out-Null
        continue
    }

    $webEvents = @(Read-WebEvents -Path (Join-Path $runDir "webapp-slice.log"))
    $nginxEvents = @(Read-NginxEvents -Path (Join-Path $runDir "nginx-access-slice.log"))
    $wazuhArchives = if ($IncludeWazuh) { @(Read-WazuhEvents -Path (Join-Path $runDir "wazuh-archives-slice.json") -Source "wazuh_archive") } else { @() }
    $wazuhAlerts = if ($IncludeWazuh) { @(Read-WazuhEvents -Path (Join-Path $runDir "wazuh-alerts-slice.json") -Source "wazuh_alert") } else { @() }

    $windowStart = $start
    $windowIndex = 0
    while ($windowStart -lt $end) {
        $windowEnd = $windowStart.AddSeconds($WindowSeconds)
        $webWin = @($webEvents | Where-Object { $_.TimestampUtc -ge $windowStart -and $_.TimestampUtc -lt $windowEnd })
        $nginxWin = @($nginxEvents | Where-Object { $_.TimestampUtc -ge $windowStart -and $_.TimestampUtc -lt $windowEnd })
        $archiveWin = @($wazuhArchives | Where-Object { $_.TimestampUtc -ge $windowStart -and $_.TimestampUtc -lt $windowEnd })
        $alertWin = @($wazuhAlerts | Where-Object { $_.TimestampUtc -ge $windowStart -and $_.TimestampUtc -lt $windowEnd })
        $completed = @($webWin | Where-Object { [string](Get-Value -Object $_.Event -Names @("event_type")) -eq "request_completed" })
        $statusBuckets = @{ "2xx" = 0; "3xx" = 0; "4xx" = 0; "5xx" = 0; "error" = 0 }
        $latencies = New-Object System.Collections.Generic.List[double]
        $healthLatencies = New-Object System.Collections.Generic.List[double]
        $healthCount = 0
        $healthFailed = 0
        $paths = New-Object System.Collections.Generic.List[string]
        $sources = New-Object System.Collections.Generic.List[string]

        foreach ($entry in $completed) {
            $status = [int](Get-Value -Object $entry.Event -Names @("status_code") -Default 0)
            Add-StatusBucket -StatusCode $status -Buckets $statusBuckets
            $path = [string](Get-Value -Object $entry.Event -Names @("path", "endpoint") -Default "")
            if ($path) { $paths.Add($path) | Out-Null }
            $sourceIp = [string](Get-Value -Object $entry.Event -Names @("source_ip") -Default "")
            if ($sourceIp) { $sources.Add($sourceIp) | Out-Null }
            $rt = Convert-ToDoubleOrNull (Get-Value -Object $entry.Event -Names @("response_time_ms", "request_duration_ms") -Default $null)
            if ($null -ne $rt) { $latencies.Add($rt) | Out-Null }
            if ($path -eq "/health") {
                $healthCount++
                if ($status -ge 400) { $healthFailed++ }
            }
            $hlt = Convert-ToDoubleOrNull (Get-Value -Object $entry.Event -Names @("health_check_latency_ms") -Default $null)
            if ($null -ne $hlt) { $healthLatencies.Add($hlt) | Out-Null }
        }

        foreach ($entry in $nginxWin) {
            Add-StatusBucket -StatusCode $entry.StatusCode -Buckets $statusBuckets
            if ($entry.Path) { $paths.Add([string]$entry.Path) | Out-Null }
            if ($entry.SourceIp) { $sources.Add([string]$entry.SourceIp) | Out-Null }
        }

        $sourceSummary = Get-SourceSummary -Sources $sources.ToArray()
        $requestCount = [Math]::Max($completed.Count, $nginxWin.Count)
        $rate = [Math]::Round([double]$requestCount / [double]$WindowSeconds, 3)
        $errorRate = if ($requestCount -gt 0) { [Math]::Round([double]$statusBuckets["error"] / [double]$requestCount, 3) } else { 0 }
        $uniquePathCount = @($paths.ToArray() | Where-Object { $_ } | Select-Object -Unique).Count
        $repeatedPathCount = @($paths.ToArray() | Where-Object { $_ } | Group-Object | Where-Object { $_.Count -gt 1 }).Count
        $avgLatency = if ($latencies.Count -gt 0) { [Math]::Round([double](($latencies | Measure-Object -Average).Average), 3) } else { 0 }
        $maxLatency = if ($latencies.Count -gt 0) { [Math]::Round([double](($latencies | Measure-Object -Maximum).Maximum), 3) } else { 0 }
        $avgHealth = if ($healthLatencies.Count -gt 0) { [Math]::Round([double](($healthLatencies | Measure-Object -Average).Average), 3) } else { 0 }
        $maxHealth = if ($healthLatencies.Count -gt 0) { [Math]::Round([double](($healthLatencies | Measure-Object -Maximum).Maximum), 3) } else { 0 }
        $scenario = [string](Get-Value -Object $metadata -Names @("scenario"))
        $variant = [string](Get-Value -Object $metadata -Names @("scenario_variant"))
        $stage = Get-StageLabel -Scenario $scenario -Variant $variant -WindowIndex $windowIndex -Rate $rate -TopSourceRatio $sourceSummary.Ratio -ErrorCount $statusBuckets["error"] -MaxLatency $maxLatency -HealthFailed $healthFailed
        $needsManual = ($stage -ne "baseline")
        $refs = ""
        if ($IncludeRawEvidenceRefs) {
            $refs = (@(
                "webapp-slice.log:$(@($webWin | Select-Object -First 5 | ForEach-Object { $_.Line }) -join ',')",
                "nginx-access-slice.log:$(@($nginxWin | Select-Object -First 5 | ForEach-Object { $_.Line }) -join ',')"
            ) -join ";")
        }

        $rows.Add([PSCustomObject][ordered]@{
            batch_id = $batchId
            run_id = $runId
            scenario = $scenario
            scenario_variant = $variant
            main_label = [string](Get-Value -Object $metadata -Names @("main_label"))
            sublabel = [string](Get-Value -Object $metadata -Names @("sublabel"))
            intensity = [string](Get-Value -Object $metadata -Names @("intensity"))
            actor_profile = [string](Get-Value -Object $metadata -Names @("actor_profile"))
            window_id = "$runId-window-$('{0:D4}' -f $windowIndex)"
            window_index = $windowIndex
            window_start_utc = $windowStart.ToString("o")
            window_end_utc = $windowEnd.ToString("o")
            window_seconds = $WindowSeconds
            request_count = $requestCount
            request_rate_per_second = $rate
            nginx_request_count = $nginxWin.Count
            webapp_event_count = $webWin.Count
            request_completed_count = $completed.Count
            unique_source_ip_count = $sourceSummary.Count
            dominant_source_ip = $sourceSummary.Dominant
            top_source_ip_ratio = $sourceSummary.Ratio
            unique_path_count = $uniquePathCount
            repeated_path_count = $repeatedPathCount
            status_2xx_count = [int]$statusBuckets["2xx"]
            status_3xx_count = [int]$statusBuckets["3xx"]
            status_4xx_count = [int]$statusBuckets["4xx"]
            status_5xx_count = [int]$statusBuckets["5xx"]
            error_status_count = [int]$statusBuckets["error"]
            error_rate = $errorRate
            avg_response_time_ms = $avgLatency
            max_response_time_ms = $maxLatency
            p95_response_time_ms = Get-Percentile -Values $latencies.ToArray()
            health_check_count = $healthCount
            health_check_failed_count = $healthFailed
            avg_health_check_latency_ms = $avgHealth
            max_health_check_latency_ms = $maxHealth
            nginx_error_count = 0
            wazuh_archive_event_count = $archiveWin.Count
            wazuh_alert_event_count = $alertWin.Count
            stage_label = $stage
            incident_label = [string](Get-Value -Object $metadata -Names @("main_label"))
            needs_manual_stage_label = [bool]$needsManual
            raw_evidence_refs = $refs
        }) | Out-Null

        $windowIndex++
        $windowStart = $windowStart.AddSeconds($StepSeconds)
    }
}

$rowArray = $rows.ToArray()
$rowArray | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
$rowArray | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

[ordered]@{
    batch_id = $batchId
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    window_seconds = $WindowSeconds
    step_seconds = $StepSeconds
    row_count = $rowArray.Count
    include_wazuh = [bool]$IncludeWazuh
    warnings = $warnings.ToArray()
    csv_path = $csvPath
    json_path = $jsonPath
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

Write-Host "Window rows: $($rowArray.Count)"
Write-Host "CSV: $csvPath"
Write-Host "JSON: $jsonPath"
Write-Host "Summary: $summaryPath"
