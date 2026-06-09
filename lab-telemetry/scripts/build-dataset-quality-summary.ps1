<#
.SYNOPSIS
Builds a per-run dataset quality and feature extraction preview for a completed batch.

.PARAMETER BatchManifestPath
Path to the dataset batch manifest.

.PARAMETER OutputPath
Optional CSV output path. Defaults to exports\dataset-quality\<batch_id>-quality-summary.csv.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BatchManifestPath,

    [string]$OutputPath
)

$ErrorActionPreference = "Stop"

$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Join-Path (Get-Location) "scripts" }
$RepoRoot = Split-Path -Path $ScriptRoot -Parent
$VerifiedRunsRoot = Join-Path $RepoRoot "exports\verified-runs"
$DefaultQualityRoot = Join-Path $RepoRoot "exports\dataset-quality"

$script:MissingFileWarnings = New-Object System.Collections.Generic.List[string]
$script:ParseWarnings = New-Object System.Collections.Generic.List[string]

function Write-Step {
    param([string]$Message)
    Write-Host ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Message)
}

function Add-MissingFileWarning {
    param(
        [string]$RunId,
        [string]$Description,
        [string]$Path
    )

    $message = "Run $RunId missing $Description file: $Path"
    $script:MissingFileWarnings.Add($message) | Out-Null
    Write-Host "[WARN] $message" -ForegroundColor Yellow
}

function Add-ParseWarning {
    param([string]$Message)

    $script:ParseWarnings.Add($Message) | Out-Null
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Resolve-ExistingInputPath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    if (Test-Path -LiteralPath $Path) {
        return (Resolve-Path -LiteralPath $Path).Path
    }

    return [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
}

function Resolve-OutputFilePath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
}

function Read-OptionalJsonFile {
    param(
        [string]$RunId,
        [string]$Description,
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-MissingFileWarning -RunId $RunId -Description $Description -Path $Path
        return $null
    }

    try {
        return (Get-Content -Raw -LiteralPath $Path -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
    }
    catch {
        Add-ParseWarning -Message "Run $RunId could not parse $Description JSON: $Path. $($_.Exception.Message)"
        return $null
    }
}

function Read-OptionalLines {
    param(
        [string]$RunId,
        [string]$Description,
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-MissingFileWarning -RunId $RunId -Description $Description -Path $Path
        return @()
    }

    try {
        return @(Get-Content -LiteralPath $Path -ErrorAction Stop)
    }
    catch {
        Add-ParseWarning -Message "Run $RunId could not read $Description file: $Path. $($_.Exception.Message)"
        return @()
    }
}

function Get-FirstObjectValue {
    param(
        [object[]]$Objects,
        [string[]]$Names,
        [object]$Default = $null
    )

    foreach ($object in $Objects) {
        if ($null -eq $object) {
            continue
        }

        foreach ($name in $Names) {
            $property = $object.PSObject.Properties[$name]
            if ($property -and $null -ne $property.Value) {
                if ($property.Value -is [string] -and [string]::IsNullOrWhiteSpace([string]$property.Value)) {
                    continue
                }

                return $property.Value
            }
        }
    }

    return $Default
}

function Get-MapCount {
    param(
        [object]$Map,
        [string]$Key
    )

    if ($null -eq $Map) {
        return 0
    }

    $property = $Map.PSObject.Properties[$Key]
    if (-not $property -or $null -eq $property.Value) {
        return 0
    }

    $parsed = 0
    if ([int]::TryParse([string]$property.Value, [ref]$parsed)) {
        return $parsed
    }

    return 0
}

function Convert-ToIntOrZero {
    param([object]$Value)

    if ($null -eq $Value) {
        return 0
    }

    $parsed = 0
    if ([int]::TryParse([string]$Value, [ref]$parsed)) {
        return $parsed
    }

    return 0
}

function Convert-ToDoubleOrNull {
    param([object]$Value)

    if ($null -eq $Value) {
        return $null
    }

    $parsed = 0.0
    $styles = [System.Globalization.NumberStyles]::Float
    if ([double]::TryParse([string]$Value, $styles, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
        return $parsed
    }

    if ([double]::TryParse([string]$Value, [ref]$parsed)) {
        return $parsed
    }

    return $null
}

function Get-RoundedAverage {
    param([System.Collections.Generic.List[double]]$Values)

    if ($Values.Count -eq 0) {
        return $null
    }

    $average = ($Values | Measure-Object -Average).Average
    return [Math]::Round([double]$average, 3)
}

function Get-RoundedMaximum {
    param([System.Collections.Generic.List[double]]$Values)

    if ($Values.Count -eq 0) {
        return $null
    }

    $maximum = ($Values | Measure-Object -Maximum).Maximum
    return [Math]::Round([double]$maximum, 3)
}

function Get-RoundedPercentile {
    param(
        [System.Collections.Generic.List[double]]$Values,
        [double]$Percentile = 0.95
    )

    if ($Values.Count -eq 0) {
        return $null
    }

    $sorted = @($Values | Sort-Object)
    $index = [Math]::Ceiling($Percentile * $sorted.Count) - 1
    $index = [Math]::Max(0, [Math]::Min($sorted.Count - 1, $index))
    return [Math]::Round([double]$sorted[$index], 3)
}

function Get-CountMap {
    param(
        [object[]]$Rows,
        [string]$PropertyName
    )

    $counts = [ordered]@{}
    foreach ($row in $Rows) {
        $key = [string]$row.$PropertyName
        if ([string]::IsNullOrWhiteSpace($key)) {
            $key = "(blank)"
        }

        if ($counts.Contains($key)) {
            $counts[$key] = [int]$counts[$key] + 1
        }
        else {
            $counts[$key] = 1
        }
    }

    return $counts
}

function Get-SourceDistribution {
    param([string[]]$Sources)

    $validSources = @($Sources | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($validSources.Count -eq 0) {
        return [PSCustomObject]@{
            SourceCount = 0
            DominantSourceIp = $null
            SameSourceRequestRatio = 0.0
        }
    }

    $groups = @($validSources | Group-Object | Sort-Object Count -Descending)
    $dominant = $groups[0]
    return [PSCustomObject]@{
        SourceCount = $groups.Count
        DominantSourceIp = [string]$dominant.Name
        SameSourceRequestRatio = [Math]::Round(([double]$dominant.Count / [double]$validSources.Count), 3)
    }
}

function Get-NginxSourceIps {
    param([string[]]$Lines)

    return @($Lines | ForEach-Object {
        $match = [regex]::Match([string]$_, '^(?<source_ip>\S+)\s+')
        if ($match.Success) {
            $match.Groups["source_ip"].Value
        }
    })
}

function Get-NginxStatusCodes {
    param([string[]]$Lines)

    return @($Lines | ForEach-Object {
        $match = [regex]::Match([string]$_, '"(?:GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)\s+[^"]+"\s+(?<status>\d{3})\s+')
        if ($match.Success) {
            Convert-ToIntOrZero -Value $match.Groups["status"].Value
        }
    })
}

function Get-NginxTargets {
    param([string[]]$Lines)

    return @($Lines | ForEach-Object {
        $match = [regex]::Match([string]$_, '"(?:GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)\s+(?<target>\S+)')
        if ($match.Success) {
            [string]$match.Groups["target"].Value
        }
    })
}

function Get-ObjectTimestampUtc {
    param([object]$Object)

    foreach ($name in @("timestamp", "@timestamp", "time", "event_time")) {
        $value = Get-FirstObjectValue -Objects @($Object) -Names @($name) -Default $null
        if ($null -eq $value) {
            continue
        }

        try {
            return ([DateTimeOffset]::Parse([string]$value)).UtcDateTime
        }
        catch {
        }
    }

    return $null
}

function Get-RunDurationSeconds {
    param(
        [object]$Metadata,
        [object]$Manifest
    )

    $start = Get-FirstObjectValue -Objects @($Metadata, $Manifest) -Names @("start_time_utc", "window_start_utc") -Default $null
    $end = Get-FirstObjectValue -Objects @($Metadata, $Manifest) -Names @("end_time_utc", "window_end_utc") -Default $null
    try {
        $startDto = [DateTimeOffset]::Parse([string]$start)
        $endDto = [DateTimeOffset]::Parse([string]$end)
        return [Math]::Max(0.001, [Math]::Round(($endDto - $startDto).TotalSeconds, 3))
    }
    catch {
        return $null
    }
}

function Test-BurstSearchQuery {
    param([string]$Query)

    return (-not [string]::IsNullOrWhiteSpace($Query) -and $Query -like "*burst-*")
}

function Test-HumanRepeatedSearchQuery {
    param([string]$Query)

    return (-not [string]::IsNullOrWhiteSpace($Query) -and $Query -like "case review *")
}

$resolvedBatchManifestPath = Resolve-ExistingInputPath -Path $BatchManifestPath
if (-not (Test-Path -LiteralPath $resolvedBatchManifestPath -PathType Leaf)) {
    Write-Host "Batch manifest not found: $resolvedBatchManifestPath" -ForegroundColor Red
    exit 1
}

try {
    $batch = Get-Content -Raw -LiteralPath $resolvedBatchManifestPath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
}
catch {
    Write-Host "Failed to parse batch manifest JSON: $resolvedBatchManifestPath" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

$batchId = [string](Get-FirstObjectValue -Objects @($batch) -Names @("batch_id") -Default "")
if ([string]::IsNullOrWhiteSpace($batchId)) {
    $batchId = [System.IO.Path]::GetFileName((Split-Path -Path $resolvedBatchManifestPath -Parent))
}

$safeBatchId = $batchId -replace '[^A-Za-z0-9._-]', '_'
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $DefaultQualityRoot "$safeBatchId-quality-summary.csv"
}

$resolvedOutputPath = Resolve-OutputFilePath -Path $OutputPath
$jsonOutputPath = [System.IO.Path]::ChangeExtension($resolvedOutputPath, ".json")
$outputDirectory = Split-Path -Path $resolvedOutputPath -Parent
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

Write-Host "============================================================"
Write-Host "Coding Fest 2026 XDR Dataset Quality Summary"
Write-Host "============================================================"
Write-Host "BatchManifestPath: $resolvedBatchManifestPath"
Write-Host "BatchId:           $batchId"
Write-Host "CSV OutputPath:    $resolvedOutputPath"
Write-Host "JSON OutputPath:   $jsonOutputPath"

$rows = New-Object System.Collections.Generic.List[object]
$runs = @($batch.runs)

foreach ($run in $runs) {
    $runId = [string](Get-FirstObjectValue -Objects @($run) -Names @("run_id") -Default "")
    if ([string]::IsNullOrWhiteSpace($runId)) {
        $runId = "unknown-run-$($rows.Count + 1)"
        Add-ParseWarning -Message "Batch run at sequence $($rows.Count + 1) has no run_id; using $runId."
    }

    Write-Step "Reading verified evidence for $runId"

    $safeRunId = $runId -replace '[^A-Za-z0-9._-]', '_'
    $runDirectory = Join-Path $VerifiedRunsRoot $safeRunId
    $manifestPath = Join-Path $runDirectory "manifest.json"
    $metadataPath = Join-Path $runDirectory "metadata.json"
    $webappPath = Join-Path $runDirectory "webapp-slice.log"
    $nginxPath = Join-Path $runDirectory "nginx-access-slice.log"
    $wazuhSummaryPath = Join-Path $runDirectory "wazuh-evidence-summary.json"

    $manifest = Read-OptionalJsonFile -RunId $runId -Description "verified-run manifest" -Path $manifestPath
    $metadata = Read-OptionalJsonFile -RunId $runId -Description "verified-run metadata" -Path $metadataPath
    $wazuhSummary = Read-OptionalJsonFile -RunId $runId -Description "Wazuh evidence summary" -Path $wazuhSummaryPath
    $webappLines = @(Read-OptionalLines -RunId $runId -Description "webapp slice" -Path $webappPath)
    $nginxLines = @(Read-OptionalLines -RunId $runId -Description "nginx access slice" -Path $nginxPath)

    $validWebappEvents = New-Object System.Collections.Generic.List[object]
    $invalidWebappJsonLines = 0

    foreach ($line in $webappLines) {
        if ([string]::IsNullOrWhiteSpace([string]$line)) {
            continue
        }

        try {
            $validWebappEvents.Add(($line | ConvertFrom-Json -ErrorAction Stop)) | Out-Null
        }
        catch {
            $invalidWebappJsonLines++
        }
    }

    if ($invalidWebappJsonLines -gt 0) {
        Add-ParseWarning -Message "Run $runId skipped $invalidWebappJsonLines invalid webapp JSON line(s)."
    }

    $requestCompletedCount = 0
    $searchQueryCount = 0
    $burstSearchCount = 0
    $humanRepeatedSearchCount = 0
    $pageViewCount = 0
    $loginPageViewCount = 0
    $adminAccessCount = 0
    $successfulWebLoginCount = 0
    $status2xxCount = 0
    $status3xxCount = 0
    $status4xxCount = 0
    $status5xxCount = 0
    $errorStatusCount = 0
    $healthCheckCount = 0
    $healthCheckFailedCount = 0
    $responseTimes = New-Object System.Collections.Generic.List[double]
    $requestDurations = New-Object System.Collections.Generic.List[double]
    $healthCheckLatencies = New-Object System.Collections.Generic.List[double]
    $requestCompletedSourceIps = New-Object System.Collections.Generic.List[string]
    $requestCompletedPaths = New-Object System.Collections.Generic.List[string]
    $eventTimestamps = New-Object System.Collections.Generic.List[datetime]

    foreach ($event in $validWebappEvents) {
        $eventType = [string](Get-FirstObjectValue -Objects @($event) -Names @("event_type") -Default "")
        $query = [string](Get-FirstObjectValue -Objects @($event) -Names @("query") -Default "")

        if ($eventType -eq "search_query") {
            $searchQueryCount++
            if (Test-BurstSearchQuery -Query $query) {
                $burstSearchCount++
            }
            if (Test-HumanRepeatedSearchQuery -Query $query) {
                $humanRepeatedSearchCount++
            }
        }

        if ($eventType -eq "page_view") {
            $pageViewCount++
            $pagePath = [string](Get-FirstObjectValue -Objects @($event) -Names @("path") -Default "")
            if ($pagePath -eq "/login") {
                $loginPageViewCount++
            }
        }

        if ($eventType -eq "admin_route_access") {
            $adminAccessCount++
        }

        if ($eventType -eq "web_login_attempt") {
            $loginResult = [string](Get-FirstObjectValue -Objects @($event) -Names @("reason", "result", "status") -Default "")
            if ($loginResult -match "login_success|success") {
                $successfulWebLoginCount++
            }
        }

        if ($eventType -ne "request_completed") {
            continue
        }

        $requestCompletedCount++

        $sourceIp = [string](Get-FirstObjectValue -Objects @($event) -Names @("source_ip") -Default "")
        if (-not [string]::IsNullOrWhiteSpace($sourceIp)) {
            $requestCompletedSourceIps.Add($sourceIp) | Out-Null
        }

        $statusCode = Convert-ToIntOrZero -Value (Get-FirstObjectValue -Objects @($event) -Names @("status_code") -Default 0)
        if ($statusCode -ge 200 -and $statusCode -lt 300) {
            $status2xxCount++
        }
        elseif ($statusCode -ge 300 -and $statusCode -lt 400) {
            $status3xxCount++
        }
        elseif ($statusCode -ge 400 -and $statusCode -lt 500) {
            $status4xxCount++
            $errorStatusCount++
        }
        elseif ($statusCode -ge 500 -and $statusCode -lt 600) {
            $status5xxCount++
            $errorStatusCount++
        }

        $responseTime = Convert-ToDoubleOrNull -Value (Get-FirstObjectValue -Objects @($event) -Names @("response_time_ms") -Default $null)
        if ($null -ne $responseTime) {
            $responseTimes.Add($responseTime) | Out-Null
        }

        $requestDuration = Convert-ToDoubleOrNull -Value (Get-FirstObjectValue -Objects @($event) -Names @("request_duration_ms") -Default $null)
        if ($null -ne $requestDuration) {
            $requestDurations.Add($requestDuration) | Out-Null
        }

        $path = [string](Get-FirstObjectValue -Objects @($event) -Names @("path", "endpoint") -Default "")
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            $requestCompletedPaths.Add($path) | Out-Null
        }
        if ($path -eq "/health") {
            $healthCheckCount++
            if ($statusCode -ge 400) {
                $healthCheckFailedCount++
            }
        }

        $healthLatency = Convert-ToDoubleOrNull -Value (Get-FirstObjectValue -Objects @($event) -Names @("health_check_latency_ms") -Default $null)
        if ($null -ne $healthLatency) {
            $healthCheckLatencies.Add($healthLatency) | Out-Null
        }

        $eventTimestamp = Get-ObjectTimestampUtc -Object $event
        if ($null -ne $eventTimestamp) {
            $eventTimestamps.Add($eventTimestamp) | Out-Null
        }
    }

    if ($requestCompletedCount -eq 0 -and $nginxLines.Count -gt 0) {
        foreach ($statusCode in @(Get-NginxStatusCodes -Lines $nginxLines)) {
            if ($statusCode -ge 200 -and $statusCode -lt 300) { $status2xxCount++ }
            elseif ($statusCode -ge 300 -and $statusCode -lt 400) { $status3xxCount++ }
            elseif ($statusCode -ge 400 -and $statusCode -lt 500) { $status4xxCount++; $errorStatusCount++ }
            elseif ($statusCode -ge 500 -and $statusCode -lt 600) { $status5xxCount++; $errorStatusCount++ }
        }
    }

    $verificationValue = Get-FirstObjectValue -Objects @($manifest) -Names @("verification_passed") -Default $null
    if ($null -eq $verificationValue) {
        $verificationValue = ([string](Get-FirstObjectValue -Objects @($run) -Names @("verification_status") -Default "") -eq "passed")
    }

    $archiveEventCount = Convert-ToIntOrZero -Value (Get-FirstObjectValue -Objects @($wazuhSummary, $manifest.wazuh_evidence) -Names @("archive_event_count") -Default 0)
    $alertEventCount = Convert-ToIntOrZero -Value (Get-FirstObjectValue -Objects @($wazuhSummary, $manifest.wazuh_evidence) -Names @("alert_event_count") -Default 0)
    $archiveLocationCounts = Get-FirstObjectValue -Objects @($wazuhSummary) -Names @("archive_location_counts") -Default $null
    $decoderCounts = Get-FirstObjectValue -Objects @($wazuhSummary) -Names @("decoder_counts") -Default $null
    $wazuhArchivesSlicePath = Join-Path $runDirectory "wazuh-archives-slice.json"
    $wazuhArchiveEvidencePresent = ((Test-Path -LiteralPath $wazuhArchivesSlicePath -PathType Leaf) -and $archiveEventCount -gt 0)
    $webappSourceDistribution = Get-SourceDistribution -Sources $requestCompletedSourceIps.ToArray()
    $nginxSourceDistribution = Get-SourceDistribution -Sources (Get-NginxSourceIps -Lines $nginxLines)
    $attackerSourceIp = [string](Get-FirstObjectValue -Objects @($manifest, $metadata) -Names @("attacker_source_ip") -Default "")
    $metadataMatchesWebapp = if ([string]::IsNullOrWhiteSpace($attackerSourceIp) -or [string]::IsNullOrWhiteSpace([string]$webappSourceDistribution.DominantSourceIp)) {
        $null
    }
    else {
        $attackerSourceIp -eq [string]$webappSourceDistribution.DominantSourceIp
    }
    $metadataMatchesNginx = if ([string]::IsNullOrWhiteSpace($attackerSourceIp) -or [string]::IsNullOrWhiteSpace([string]$nginxSourceDistribution.DominantSourceIp)) {
        $null
    }
    else {
        $attackerSourceIp -eq [string]$nginxSourceDistribution.DominantSourceIp
    }

    $runDurationSeconds = Get-RunDurationSeconds -Metadata $metadata -Manifest $manifest
    $effectiveRequestCount = [Math]::Max($requestCompletedCount, $nginxLines.Count)
    $requestRatePerSecond = if ($runDurationSeconds) { [Math]::Round(([double]$effectiveRequestCount / [double]$runDurationSeconds), 3) } else { $null }
    $peakRequestRatePerSecond = 0
    if ($eventTimestamps.Count -gt 0) {
        $peakRequestRatePerSecond = [int]((@($eventTimestamps | ForEach-Object { $_.ToString("yyyy-MM-ddTHH:mm:ssZ") }) | Group-Object | Sort-Object Count -Descending | Select-Object -First 1).Count)
    }
    $nginxTargets = @(Get-NginxTargets -Lines $nginxLines)
    $allPaths = @($requestCompletedPaths.ToArray()) + $nginxTargets
    $uniquePathCount = @($allPaths | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique).Count
    $repeatedPathCount = @($allPaths | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Group-Object | Where-Object { $_.Count -gt 1 }).Count
    $topSourceRatio = [Math]::Max([double]$webappSourceDistribution.SameSourceRequestRatio, [double]$nginxSourceDistribution.SameSourceRequestRatio)
    $observedSourceCount = [Math]::Max([int]$webappSourceDistribution.SourceCount, [int]$nginxSourceDistribution.SourceCount)
    $sourceDistributionSummary = "webapp_sources=$($webappSourceDistribution.SourceCount);nginx_sources=$($nginxSourceDistribution.SourceCount);webapp_ratio=$($webappSourceDistribution.SameSourceRequestRatio);nginx_ratio=$($nginxSourceDistribution.SameSourceRequestRatio)"

    $row = [PSCustomObject][ordered]@{
        run_id = $runId
        scenario = [string](Get-FirstObjectValue -Objects @($manifest, $metadata, $run, $wazuhSummary) -Names @("scenario") -Default "")
        label = [string](Get-FirstObjectValue -Objects @($manifest, $metadata, $run, $wazuhSummary) -Names @("main_label", "label") -Default "")
        sublabel = [string](Get-FirstObjectValue -Objects @($manifest, $metadata, $wazuhSummary) -Names @("sublabel") -Default "")
        scenario_variant = [string](Get-FirstObjectValue -Objects @($manifest, $metadata, $wazuhSummary) -Names @("scenario_variant") -Default "")
        actor_profile = [string](Get-FirstObjectValue -Objects @($manifest, $metadata, $run, $wazuhSummary) -Names @("actor_profile") -Default "")
        intensity = [string](Get-FirstObjectValue -Objects @($manifest, $metadata, $run, $wazuhSummary) -Names @("intensity") -Default "")
        benign_activity_level = [string](Get-FirstObjectValue -Objects @($manifest, $metadata, $wazuhSummary) -Names @("benign_activity_level") -Default "")
        generator_version = [string](Get-FirstObjectValue -Objects @($manifest, $metadata, $wazuhSummary) -Names @("generator_version") -Default "")
        planned_request_count = Convert-ToIntOrZero -Value (Get-FirstObjectValue -Objects @($manifest, $metadata, $wazuhSummary) -Names @("planned_request_count") -Default 0)
        actual_request_count = Convert-ToIntOrZero -Value (Get-FirstObjectValue -Objects @($manifest, $metadata, $wazuhSummary) -Names @("actual_request_count") -Default 0)
        safety_limit_applied = Get-FirstObjectValue -Objects @($manifest, $metadata, $wazuhSummary) -Names @("safety_limit_applied") -Default $null
        target_endpoint_family = [string](Get-FirstObjectValue -Objects @($manifest, $metadata, $wazuhSummary) -Names @("target_endpoint_family") -Default "")
        attacker_host_type = [string](Get-FirstObjectValue -Objects @($manifest, $metadata) -Names @("attacker_host_type") -Default "")
        attacker_source_ip = $attackerSourceIp
        target_web_base = [string](Get-FirstObjectValue -Objects @($manifest, $metadata) -Names @("target_web_base") -Default "")
        traffic_tool = [string](Get-FirstObjectValue -Objects @($manifest, $metadata) -Names @("traffic_tool") -Default "")
        attack_mode = [string](Get-FirstObjectValue -Objects @($manifest, $metadata) -Names @("attack_mode") -Default "")
        distributed = Get-FirstObjectValue -Objects @($manifest, $metadata) -Names @("distributed") -Default $null
        source_count = Get-FirstObjectValue -Objects @($manifest, $metadata) -Names @("source_count") -Default $null
        expected_source_count = Get-FirstObjectValue -Objects @($manifest, $metadata) -Names @("expected_source_count") -Default $null
        expected_distributed = Get-FirstObjectValue -Objects @($manifest, $metadata) -Names @("expected_distributed") -Default $null
        observed_webapp_source_count = $webappSourceDistribution.SourceCount
        observed_nginx_source_count = $nginxSourceDistribution.SourceCount
        dominant_webapp_source_ip = $webappSourceDistribution.DominantSourceIp
        dominant_nginx_source_ip = $nginxSourceDistribution.DominantSourceIp
        webapp_same_source_request_ratio = $webappSourceDistribution.SameSourceRequestRatio
        nginx_same_source_request_ratio = $nginxSourceDistribution.SameSourceRequestRatio
        source_ip_metadata_matches_webapp = $metadataMatchesWebapp
        source_ip_metadata_matches_nginx = $metadataMatchesNginx
        ddos_candidate_by_webapp_sources = ($webappSourceDistribution.SourceCount -gt 1)
        ddos_candidate_by_nginx_sources = ($nginxSourceDistribution.SourceCount -gt 1)
        distributed_evidence_confirmed = ($observedSourceCount -gt 1)
        observed_source_count = $observedSourceCount
        top_source_ip_ratio = $topSourceRatio
        source_distribution_summary = $sourceDistributionSummary
        verification_passed = [bool]$verificationValue
        archive_event_count = $archiveEventCount
        alert_event_count = $alertEventCount
        wazuh_archive_evidence_present = $wazuhArchiveEvidencePresent
        wazuh_webapp_log_count = Get-MapCount -Map $archiveLocationCounts -Key "/home/ubuntu/web-lab/logs/webapp.log"
        wazuh_nginx_access_count = Get-MapCount -Map $archiveLocationCounts -Key "/var/log/nginx/access.log"
        wazuh_json_decoder_count = Get-MapCount -Map $decoderCounts -Key "json"
        wazuh_web_accesslog_decoder_count = Get-MapCount -Map $decoderCounts -Key "web-accesslog"
        webapp_slice_lines = $webappLines.Count
        nginx_slice_lines = $nginxLines.Count
        invalid_webapp_json_lines = $invalidWebappJsonLines
        request_completed_count = $requestCompletedCount
        webapp_request_completed_count = $requestCompletedCount
        nginx_request_count = $nginxLines.Count
        run_duration_seconds = $runDurationSeconds
        request_rate_per_second = $requestRatePerSecond
        peak_request_rate_per_second = $peakRequestRatePerSecond
        unique_path_count = $uniquePathCount
        repeated_path_count = $repeatedPathCount
        search_query_count = $searchQueryCount
        burst_search_count = $burstSearchCount
        human_repeated_search_count = $humanRepeatedSearchCount
        page_view_count = $pageViewCount
        login_page_view_count = $loginPageViewCount
        admin_access_count = $adminAccessCount
        successful_web_login_count = $successfulWebLoginCount
        status_2xx_count = $status2xxCount
        status_3xx_count = $status3xxCount
        status_4xx_count = $status4xxCount
        status_5xx_count = $status5xxCount
        error_status_count = $errorStatusCount
        error_rate = if ($requestCompletedCount -gt 0) { [Math]::Round(([double]$errorStatusCount / [double]$requestCompletedCount), 3) } else { 0 }
        avg_response_time_ms = Get-RoundedAverage -Values $responseTimes
        max_response_time_ms = Get-RoundedMaximum -Values $responseTimes
        p95_response_time_ms = Get-RoundedPercentile -Values $responseTimes
        avg_request_duration_ms = Get-RoundedAverage -Values $requestDurations
        max_request_duration_ms = Get-RoundedMaximum -Values $requestDurations
        health_check_count = $healthCheckCount
        health_check_failed_count = $healthCheckFailedCount
        avg_health_check_latency_ms = Get-RoundedAverage -Values $healthCheckLatencies
        max_health_check_latency_ms = Get-RoundedMaximum -Values $healthCheckLatencies
        nginx_error_count = 0
    }

    $rows.Add($row) | Out-Null
}

$rowArray = $rows.ToArray()
$missingFileWarningArray = $script:MissingFileWarnings.ToArray()
$parseWarningArray = $script:ParseWarnings.ToArray()
$invalidWebappJsonLineCount = 0
if ($rowArray.Count -gt 0) {
    $invalidWebappJsonLineCount = [int](($rowArray | Measure-Object -Property invalid_webapp_json_lines -Sum).Sum)
}

$rowArray | Export-Csv -LiteralPath $resolvedOutputPath -NoTypeInformation -Encoding UTF8

$jsonSummary = [ordered]@{
    batch_id = $batchId
    total_runs = $rows.Count
    runs_by_scenario = Get-CountMap -Rows $rowArray -PropertyName "scenario"
    runs_by_label = Get-CountMap -Rows $rowArray -PropertyName "label"
    missing_file_warnings = $missingFileWarningArray
    parse_warnings = $parseWarningArray
    invalid_webapp_json_line_count = $invalidWebappJsonLineCount
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    csv_path = $resolvedOutputPath
}

$jsonSummary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonOutputPath -Encoding UTF8

Write-Host "`n============================================================"
Write-Host "DATASET QUALITY SUMMARY"
Write-Host "============================================================"
$rowArray |
    Select-Object run_id, scenario, scenario_variant, benign_activity_level, request_completed_count, search_query_count, human_repeated_search_count, burst_search_count, status_2xx_count, avg_response_time_ms, max_response_time_ms, archive_event_count, alert_event_count |
    Format-Table -AutoSize
Write-Host "Runs:                  $($rows.Count)"
Write-Host "Missing file warnings: $($script:MissingFileWarnings.Count)"
Write-Host "Parse warnings:        $($script:ParseWarnings.Count)"
Write-Host "CSV:                   $resolvedOutputPath"
Write-Host "JSON:                  $jsonOutputPath"
Write-Host "Dataset quality summary completed." -ForegroundColor Green

exit 0
