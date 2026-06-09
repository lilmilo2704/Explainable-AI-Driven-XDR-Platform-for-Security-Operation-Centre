<#
.SYNOPSIS
Builds a one-row-per-run ML feature table from a batch manifest and verified-run evidence.

.PARAMETER BatchManifestPath
Path to the dataset batch manifest.

.PARAMETER OutputDir
Directory for feature outputs. Defaults to exports\ml-features.

.PARAMETER IncludeRawEvidence
Also writes separate feature outputs with raw local and Wazuh evidence text embedded in CSV/JSON columns.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BatchManifestPath,

    [string]$OutputDir = "exports\ml-features",

    [switch]$IncludeRawEvidence
)

$ErrorActionPreference = "Stop"

$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Join-Path (Get-Location) "scripts" }
$RepoRoot = Split-Path -Path $ScriptRoot -Parent
$VerifiedRunsRoot = Join-Path $RepoRoot "exports\verified-runs"

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

function Resolve-InputPath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    if (Test-Path -LiteralPath $Path) {
        return (Resolve-Path -LiteralPath $Path).Path
    }

    return [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
}

function Resolve-OutputDirectory {
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
        [string]$Path,
        [switch]$Optional
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        if (-not $Optional) {
            Add-MissingFileWarning -RunId $RunId -Description $Description -Path $Path
        }
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
        [string]$Path,
        [switch]$Optional
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        if (-not $Optional) {
            Add-MissingFileWarning -RunId $RunId -Description $Description -Path $Path
        }
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

function Read-RawTextOrEmpty {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return ""
    }

    return (Get-Content -Raw -LiteralPath $Path -ErrorAction Stop)
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

function Convert-ToBoolOrFalse {
    param([object]$Value)

    if ($null -eq $Value) {
        return $false
    }

    if ($Value -is [bool]) {
        return [bool]$Value
    }

    $parsed = $false
    if ([bool]::TryParse([string]$Value, [ref]$parsed)) {
        return $parsed
    }

    return $false
}

function Convert-ToTextOrEmpty {
    param([object]$Value)

    if ($null -eq $Value) {
        return ""
    }

    return [string]$Value
}

function Normalize-MainLabel {
    param([object]$Value)

    $label = Convert-ToTextOrEmpty -Value $Value
    if ($label -eq "DoS") {
        return "DoS_DDoS"
    }

    return $label
}

function Get-RoundedAverageOrZero {
    param([System.Collections.Generic.List[double]]$Values)

    if ($Values.Count -eq 0) {
        return 0
    }

    $average = ($Values | Measure-Object -Average).Average
    return [Math]::Round([double]$average, 3)
}

function Get-RoundedMaximumOrZero {
    param([System.Collections.Generic.List[double]]$Values)

    if ($Values.Count -eq 0) {
        return 0
    }

    $maximum = ($Values | Measure-Object -Maximum).Maximum
    return [Math]::Round([double]$maximum, 3)
}

function Get-RoundedMinimumOrZero {
    param([System.Collections.Generic.List[double]]$Values)

    if ($Values.Count -eq 0) {
        return 0
    }

    $minimum = ($Values | Measure-Object -Minimum).Minimum
    return [Math]::Round([double]$minimum, 3)
}

function Get-RoundedPercentileOrZero {
    param(
        [System.Collections.Generic.List[double]]$Values,
        [double]$Percentile = 0.95
    )

    if ($Values.Count -eq 0) {
        return 0
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
            DominantSourceIp = ""
            SameSourceRequestRatio = 0
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
        return 0
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

function Get-ExistingFilePathOrEmpty {
    param([string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return ""
}

function New-RawEvidenceCombinedText {
    param(
        [string]$RawWebappLogs,
        [string]$RawNginxAccessLogs,
        [string]$RawAuthLogs,
        [string]$RawWazuhArchives,
        [string]$RawWazuhAlerts
    )

    return @(
        "=== WEBAPP LOGS ==="
        $RawWebappLogs
        "=== NGINX ACCESS LOGS ==="
        $RawNginxAccessLogs
        "=== AUTH LOGS ==="
        $RawAuthLogs
        "=== WAZUH ARCHIVES ==="
        $RawWazuhArchives
        "=== WAZUH ALERTS ==="
        $RawWazuhAlerts
    ) -join "`r`n"
}

function Add-RawContentColumns {
    param(
        [object]$FeatureRow,
        [string]$RawWebappLogs,
        [string]$RawNginxAccessLogs,
        [string]$RawAuthLogs,
        [string]$RawWazuhArchives,
        [string]$RawWazuhAlerts
    )

    $pathColumnNames = @(
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

    $rawRow = [ordered]@{}
    foreach ($property in $FeatureRow.PSObject.Properties) {
        if ($property.Name -in $pathColumnNames) {
            continue
        }

        $rawRow[$property.Name] = $property.Value
    }

    $rawRow["raw_webapp_logs"] = $RawWebappLogs
    $rawRow["raw_nginx_access_logs"] = $RawNginxAccessLogs
    $rawRow["raw_auth_logs"] = $RawAuthLogs
    $rawRow["raw_wazuh_archives"] = $RawWazuhArchives
    $rawRow["raw_wazuh_alerts"] = $RawWazuhAlerts
    $rawRow["raw_evidence_combined"] = New-RawEvidenceCombinedText `
        -RawWebappLogs $RawWebappLogs `
        -RawNginxAccessLogs $RawNginxAccessLogs `
        -RawAuthLogs $RawAuthLogs `
        -RawWazuhArchives $RawWazuhArchives `
        -RawWazuhAlerts $RawWazuhAlerts

    return [PSCustomObject]$rawRow
}

function Get-NormalizedTextForCompare {
    param([string]$Text)

    if ($null -eq $Text) {
        return ""
    }

    return (($Text -replace "`r`n", "`n") -replace "`r", "`n").TrimEnd()
}

function Write-CsvRows {
    param(
        [object[]]$Rows,
        [string]$Path
    )

    $csvLines = @($Rows | ConvertTo-Csv -NoTypeInformation)

    try {
        Set-Content -LiteralPath $Path -Value $csvLines -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            $existingText = Get-Content -Raw -LiteralPath $Path -ErrorAction Stop
            $newText = ($csvLines -join [Environment]::NewLine)

            if ((Get-NormalizedTextForCompare -Text $existingText) -eq (Get-NormalizedTextForCompare -Text $newText)) {
                Write-Host "[WARN] CSV output is locked but already matches generated content: $Path" -ForegroundColor Yellow
                return
            }
        }

        throw
    }
}

function Add-StatusBucket {
    param(
        [int]$StatusCode,
        [hashtable]$Buckets
    )

    if ($StatusCode -ge 200 -and $StatusCode -lt 300) {
        $Buckets["2xx"]++
    }
    elseif ($StatusCode -ge 300 -and $StatusCode -lt 400) {
        $Buckets["3xx"]++
    }
    elseif ($StatusCode -ge 400 -and $StatusCode -lt 500) {
        $Buckets["4xx"]++
    }
    elseif ($StatusCode -ge 500 -and $StatusCode -lt 600) {
        $Buckets["5xx"]++
    }

    if ($StatusCode -ge 400) {
        $Buckets["error"]++
    }
}

$resolvedBatchManifestPath = Resolve-InputPath -Path $BatchManifestPath
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
$resolvedOutputDir = Resolve-OutputDirectory -Path $OutputDir
New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null

$csvOutputPath = Join-Path $resolvedOutputDir "$safeBatchId-features.csv"
$jsonOutputPath = Join-Path $resolvedOutputDir "$safeBatchId-features.json"
$rawCsvOutputPath = Join-Path $resolvedOutputDir "$safeBatchId-features-with-raw-content.csv"
$rawJsonOutputPath = Join-Path $resolvedOutputDir "$safeBatchId-features-with-raw-content.json"

Write-Host "============================================================"
Write-Host "Coding Fest 2026 XDR ML Feature Table Builder"
Write-Host "============================================================"
Write-Host "BatchManifestPath: $resolvedBatchManifestPath"
Write-Host "BatchId:           $batchId"
Write-Host "OutputDir:         $resolvedOutputDir"
Write-Host "CSV OutputPath:    $csvOutputPath"
Write-Host "JSON OutputPath:   $jsonOutputPath"
Write-Host "IncludeRawEvidence: $([bool]$IncludeRawEvidence)"
if ($IncludeRawEvidence) {
    Write-Host "Raw CSV OutputPath:  $rawCsvOutputPath"
    Write-Host "Raw JSON OutputPath: $rawJsonOutputPath"
}

$rows = New-Object System.Collections.Generic.List[object]
$rawRows = New-Object System.Collections.Generic.List[object]
$runs = @($batch.runs)

foreach ($run in $runs) {
    $runId = [string](Get-FirstObjectValue -Objects @($run) -Names @("run_id") -Default "")
    if ([string]::IsNullOrWhiteSpace($runId)) {
        $runId = "unknown-run-$($rows.Count + 1)"
        Add-ParseWarning -Message "Batch run at sequence $($rows.Count + 1) has no run_id; using $runId."
    }

    Write-Step "Building feature row for $runId"

    $safeRunId = $runId -replace '[^A-Za-z0-9._-]', '_'
    $runDirectory = Join-Path $VerifiedRunsRoot $safeRunId
    $manifestPath = Join-Path $runDirectory "manifest.json"
    $metadataPath = Join-Path $runDirectory "metadata.json"
    $wazuhSummaryPath = Join-Path $runDirectory "wazuh-evidence-summary.json"
    $wazuhArchivesPath = Join-Path $runDirectory "wazuh-archives-slice.json"
    $wazuhAlertsPath = Join-Path $runDirectory "wazuh-alerts-slice.json"
    $webappPath = Join-Path $runDirectory "webapp-slice.log"
    $nginxPath = Join-Path $runDirectory "nginx-access-slice.log"
    $authPath = Join-Path $runDirectory "auth-slice.log"

    $manifest = Read-OptionalJsonFile -RunId $runId -Description "verified-run manifest" -Path $manifestPath
    $metadata = Read-OptionalJsonFile -RunId $runId -Description "verified-run metadata" -Path $metadataPath
    $wazuhSummary = Read-OptionalJsonFile -RunId $runId -Description "Wazuh evidence summary" -Path $wazuhSummaryPath
    $webappLines = @(Read-OptionalLines -RunId $runId -Description "webapp slice" -Path $webappPath)
    $nginxLines = @(Read-OptionalLines -RunId $runId -Description "nginx access slice" -Path $nginxPath)
    $authLines = @(Read-OptionalLines -RunId $runId -Description "auth slice" -Path $authPath -Optional)

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
    $responseTimes = New-Object System.Collections.Generic.List[double]
    $requestDurations = New-Object System.Collections.Generic.List[double]
    $healthCheckLatencies = New-Object System.Collections.Generic.List[double]
    $requestCompletedSourceIps = New-Object System.Collections.Generic.List[string]
    $requestCompletedPaths = New-Object System.Collections.Generic.List[string]
    $eventTimestamps = New-Object System.Collections.Generic.List[datetime]
    $healthCheckCount = 0
    $healthCheckFailedCount = 0
    $statusBuckets = @{
        "2xx" = 0
        "3xx" = 0
        "4xx" = 0
        "5xx" = 0
        "error" = 0
    }

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
        Add-StatusBucket -StatusCode $statusCode -Buckets $statusBuckets

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
            Add-StatusBucket -StatusCode $statusCode -Buckets $statusBuckets
        }
    }

    $webappSourceDistribution = Get-SourceDistribution -Sources $requestCompletedSourceIps.ToArray()
    $nginxSourceDistribution = Get-SourceDistribution -Sources (Get-NginxSourceIps -Lines $nginxLines)
    $selectedSourceDistribution = if ($webappSourceDistribution.SourceCount -gt 0) { $webappSourceDistribution } else { $nginxSourceDistribution }

    $cleanCandidateValue = Get-FirstObjectValue -Objects @($manifest, $metadata) -Names @("clean_supervised_training_candidate", "suitable_for_clean_supervised_training") -Default $false
    $archiveEventCount = Convert-ToIntOrZero -Value (Get-FirstObjectValue -Objects @($wazuhSummary, $manifest.wazuh_evidence) -Names @("archive_event_count") -Default 0)
    $alertEventCount = Convert-ToIntOrZero -Value (Get-FirstObjectValue -Objects @($wazuhSummary, $manifest.wazuh_evidence) -Names @("alert_event_count") -Default 0)
    $wazuhArchiveEvidencePresent = ((Test-Path -LiteralPath $wazuhArchivesPath -PathType Leaf) -and $archiveEventCount -gt 0)
    $runDurationSeconds = Get-RunDurationSeconds -Metadata $metadata -Manifest $manifest
    $effectiveRequestCount = [Math]::Max($requestCompletedCount, $nginxLines.Count)
    $requestRatePerSecond = if ($runDurationSeconds -gt 0) { [Math]::Round(([double]$effectiveRequestCount / [double]$runDurationSeconds), 3) } else { 0 }
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

    $row = [PSCustomObject][ordered]@{
        run_id = $runId
        scenario = Convert-ToTextOrEmpty -Value (Get-FirstObjectValue -Objects @($manifest, $metadata, $run, $wazuhSummary) -Names @("scenario") -Default "")
        main_label = Normalize-MainLabel -Value (Get-FirstObjectValue -Objects @($manifest, $metadata, $run, $wazuhSummary) -Names @("main_label", "label") -Default "")
        sublabel = Convert-ToTextOrEmpty -Value (Get-FirstObjectValue -Objects @($manifest, $metadata, $wazuhSummary) -Names @("sublabel") -Default "")
        scenario_variant = Convert-ToTextOrEmpty -Value (Get-FirstObjectValue -Objects @($manifest, $metadata, $wazuhSummary) -Names @("scenario_variant") -Default "")
        actor_profile = Convert-ToTextOrEmpty -Value (Get-FirstObjectValue -Objects @($manifest, $metadata, $run, $wazuhSummary) -Names @("actor_profile") -Default "")
        intensity = Convert-ToTextOrEmpty -Value (Get-FirstObjectValue -Objects @($manifest, $metadata, $run, $wazuhSummary) -Names @("intensity") -Default "")
        benign_activity_level = Convert-ToTextOrEmpty -Value (Get-FirstObjectValue -Objects @($manifest, $metadata, $wazuhSummary) -Names @("benign_activity_level") -Default "")
        generator_version = Convert-ToTextOrEmpty -Value (Get-FirstObjectValue -Objects @($manifest, $metadata, $wazuhSummary) -Names @("generator_version") -Default "")
        planned_request_count = Convert-ToIntOrZero -Value (Get-FirstObjectValue -Objects @($manifest, $metadata, $wazuhSummary) -Names @("planned_request_count") -Default 0)
        actual_request_count = Convert-ToIntOrZero -Value (Get-FirstObjectValue -Objects @($manifest, $metadata, $wazuhSummary) -Names @("actual_request_count") -Default 0)
        safety_limit_applied = Convert-ToBoolOrFalse -Value (Get-FirstObjectValue -Objects @($manifest, $metadata, $wazuhSummary) -Names @("safety_limit_applied") -Default $false)
        target_endpoint_family = Convert-ToTextOrEmpty -Value (Get-FirstObjectValue -Objects @($manifest, $metadata, $wazuhSummary) -Names @("target_endpoint_family") -Default "")
        is_clean_supervised_training_candidate = Convert-ToBoolOrFalse -Value $cleanCandidateValue
        request_completed_count = $requestCompletedCount
        webapp_request_completed_count = $requestCompletedCount
        nginx_request_count = @($nginxLines | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count
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
        auth_event_count = @($authLines | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count
        webapp_line_count = @($webappLines | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count
        nginx_line_count = @($nginxLines | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count
        wazuh_archive_event_count = $archiveEventCount
        wazuh_alert_event_count = $alertEventCount
        wazuh_archive_evidence_present = $wazuhArchiveEvidencePresent
        status_2xx_count = [int]$statusBuckets["2xx"]
        status_3xx_count = [int]$statusBuckets["3xx"]
        status_4xx_count = [int]$statusBuckets["4xx"]
        status_5xx_count = [int]$statusBuckets["5xx"]
        error_status_count = [int]$statusBuckets["error"]
        error_rate = if ($requestCompletedCount -gt 0) { [Math]::Round(([double][int]$statusBuckets["error"] / [double]$requestCompletedCount), 3) } else { 0 }
        avg_response_time_ms = Get-RoundedAverageOrZero -Values $responseTimes
        max_response_time_ms = Get-RoundedMaximumOrZero -Values $responseTimes
        min_response_time_ms = Get-RoundedMinimumOrZero -Values $responseTimes
        p95_response_time_ms = Get-RoundedPercentileOrZero -Values $responseTimes
        avg_request_duration_ms = Get-RoundedAverageOrZero -Values $requestDurations
        max_request_duration_ms = Get-RoundedMaximumOrZero -Values $requestDurations
        health_check_count = $healthCheckCount
        health_check_failed_count = $healthCheckFailedCount
        avg_health_check_latency_ms = Get-RoundedAverageOrZero -Values $healthCheckLatencies
        max_health_check_latency_ms = Get-RoundedMaximumOrZero -Values $healthCheckLatencies
        nginx_error_count = 0
        observed_source_count = [int]$observedSourceCount
        dominant_source_ip = Convert-ToTextOrEmpty -Value $selectedSourceDistribution.DominantSourceIp
        same_source_request_ratio = [double]$selectedSourceDistribution.SameSourceRequestRatio
        top_source_ip_ratio = [double]$topSourceRatio
        distributed_evidence_confirmed = ([int]$observedSourceCount -gt 1)
        distributed = Convert-ToBoolOrFalse -Value (Get-FirstObjectValue -Objects @($manifest, $metadata) -Names @("distributed") -Default $false)
        source_count = Convert-ToIntOrZero -Value (Get-FirstObjectValue -Objects @($manifest, $metadata) -Names @("source_count") -Default 0)
        attacker_source_ip = Convert-ToTextOrEmpty -Value (Get-FirstObjectValue -Objects @($manifest, $metadata) -Names @("attacker_source_ip") -Default "")
        attack_mode = Convert-ToTextOrEmpty -Value (Get-FirstObjectValue -Objects @($manifest, $metadata) -Names @("attack_mode") -Default "")
        verified_run_dir = $runDirectory
        manifest_path = $manifestPath
        metadata_path = $metadataPath
        webapp_slice_path = Get-ExistingFilePathOrEmpty -Path $webappPath
        nginx_access_slice_path = Get-ExistingFilePathOrEmpty -Path $nginxPath
        auth_slice_path = Get-ExistingFilePathOrEmpty -Path $authPath
        wazuh_archives_slice_path = Get-ExistingFilePathOrEmpty -Path $wazuhArchivesPath
        wazuh_alerts_slice_path = Get-ExistingFilePathOrEmpty -Path $wazuhAlertsPath
        wazuh_evidence_summary_path = Get-ExistingFilePathOrEmpty -Path $wazuhSummaryPath
    }

    $rows.Add($row) | Out-Null

    if ($IncludeRawEvidence) {
        $rawWebappLogs = Read-RawTextOrEmpty -Path $webappPath
        $rawNginxAccessLogs = Read-RawTextOrEmpty -Path $nginxPath
        $rawAuthLogs = Read-RawTextOrEmpty -Path $authPath
        $rawWazuhArchives = Read-RawTextOrEmpty -Path $wazuhArchivesPath
        $rawWazuhAlerts = Read-RawTextOrEmpty -Path $wazuhAlertsPath

        $rawRows.Add((Add-RawContentColumns `
                    -FeatureRow $row `
                    -RawWebappLogs $rawWebappLogs `
                    -RawNginxAccessLogs $rawNginxAccessLogs `
                    -RawAuthLogs $rawAuthLogs `
                    -RawWazuhArchives $rawWazuhArchives `
                    -RawWazuhAlerts $rawWazuhAlerts)) | Out-Null
    }
}

$rowArray = $rows.ToArray()
$labelDistribution = Get-CountMap -Rows $rowArray -PropertyName "main_label"

Write-CsvRows -Rows $rowArray -Path $csvOutputPath

$jsonTable = [ordered]@{
    batch_id = $batchId
    source_batch_manifest_path = $resolvedBatchManifestPath
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    row_count = $rowArray.Count
    labels_distribution = $labelDistribution
    missing_file_warnings = $script:MissingFileWarnings.ToArray()
    parse_warnings = $script:ParseWarnings.ToArray()
    feature_rows = $rowArray
}

$jsonTable | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonOutputPath -Encoding UTF8

if ($IncludeRawEvidence) {
    $rawRowArray = $rawRows.ToArray()
    Write-CsvRows -Rows $rawRowArray -Path $rawCsvOutputPath

    $rawJsonTable = [ordered]@{
        batch_id = $batchId
        source_batch_manifest_path = $resolvedBatchManifestPath
        generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
        row_count = $rawRowArray.Count
        labels_distribution = $labelDistribution
        missing_file_warnings = $script:MissingFileWarnings.ToArray()
        parse_warnings = $script:ParseWarnings.ToArray()
        feature_rows = $rawRowArray
    }

    $rawJsonTable | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $rawJsonOutputPath -Encoding UTF8
}

Write-Host "`n============================================================"
Write-Host "ML FEATURE TABLE SUMMARY"
Write-Host "============================================================"
Write-Host "BatchId:      $batchId"
Write-Host "Rows written: $($rowArray.Count)"
Write-Host "Labels distribution:"
foreach ($property in $labelDistribution.GetEnumerator()) {
    Write-Host ("  {0}: {1}" -f $property.Key, $property.Value)
}
Write-Host "CSV:          $csvOutputPath"
Write-Host "JSON:         $jsonOutputPath"
if ($IncludeRawEvidence) {
    Write-Host "Raw CSV:      $rawCsvOutputPath"
    Write-Host "Raw JSON:     $rawJsonOutputPath"
}
Write-Host "Warnings:     missing_files=$($script:MissingFileWarnings.Count), parse=$($script:ParseWarnings.Count)"
Write-Host "ML feature table completed." -ForegroundColor Green

exit 0
