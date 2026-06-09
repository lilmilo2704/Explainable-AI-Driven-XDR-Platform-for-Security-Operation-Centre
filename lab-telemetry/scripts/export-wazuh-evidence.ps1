# export-wazuh-evidence.ps1
# Exports time-windowed Wazuh archive and alert evidence for one verified run.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$MetadataPath,

    [string]$OutputRoot = "exports\verified-runs",

    [ValidateRange(0, 3600)]
    [int]$TimePaddingSeconds = 5,

    [string]$WazuhInstance = "wazuh-server"
)

$ErrorActionPreference = "Continue"

$CurrentArchivePath = "/var/ossec/logs/archives/archives.json"
$CurrentAlertPath = "/var/ossec/logs/alerts/alerts.json"
$WazuhLogTimeZoneOffset = [TimeSpan]::FromHours(10)

function Write-Step {
    param([string]$Message)
    Write-Host ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Message)
}

function Get-ObjectValue {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($property) {
        return $property.Value
    }

    return $Default
}

function Get-FirstObjectValue {
    param(
        [object]$Object,
        [string[]]$Names,
        [object]$Default = $null
    )

    foreach ($name in $Names) {
        $value = Get-ObjectValue -Object $Object -Name $name -Default $null
        if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
            return $value
        }
    }

    return $Default
}

function Get-NestedValue {
    param(
        [object]$Object,
        [string[]]$Path
    )

    $current = $Object
    foreach ($name in $Path) {
        if ($null -eq $current) {
            return $null
        }

        $property = $current.PSObject.Properties[$name]
        if (-not $property) {
            return $null
        }

        $current = $property.Value
    }

    return $current
}

function Convert-ToUtcDateTimeOffset {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $normalized = $Value.Trim()
    if ($normalized -match "^(?<prefix>.+)(?<offset>[+-]\d{2})(?<minutes>\d{2})$") {
        $normalized = "{0}{1}:{2}" -f $matches["prefix"], $matches["offset"], $matches["minutes"]
    }

    $parsed = [DateTimeOffset]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
    if ([DateTimeOffset]::TryParse($normalized, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) {
        return $parsed.ToUniversalTime()
    }

    return $null
}

function Get-WazuhTimestampUtc {
    param([object]$Event)

    foreach ($field in @("timestamp", "@timestamp", "time", "created_at", "event_time")) {
        $value = Get-ObjectValue -Object $Event -Name $field -Default $null
        if ($value) {
            $parsed = Convert-ToUtcDateTimeOffset -Value ([string]$value)
            if ($parsed) {
                return $parsed
            }
        }
    }

    return $null
}

function Test-MultipassInstance {
    param([string]$Instance)

    & multipass exec $Instance -- true 2>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Convert-ToShellSingleQuoted {
    param([string]$Value)

    return "'{0}'" -f ($Value -replace "'", "'\''")
}

function Get-UtcDatesInWindow {
    param(
        [DateTimeOffset]$WindowStartUtc,
        [DateTimeOffset]$WindowEndUtc
    )

    $dates = New-Object System.Collections.Generic.List[DateTime]
    $date = $WindowStartUtc.UtcDateTime.Date
    $lastDate = $WindowEndUtc.UtcDateTime.Date

    while ($date -le $lastDate) {
        $dates.Add($date) | Out-Null
        $date = $date.AddDays(1)
    }

    return @($dates | ForEach-Object { $_ })
}

function Get-OffsetDatesInWindow {
    param(
        [DateTimeOffset]$WindowStartUtc,
        [DateTimeOffset]$WindowEndUtc,
        [TimeSpan]$Offset
    )

    $dates = New-Object System.Collections.Generic.List[DateTime]
    $date = $WindowStartUtc.ToOffset($Offset).Date
    $lastDate = $WindowEndUtc.ToOffset($Offset).Date

    while ($date -le $lastDate) {
        $dates.Add($date) | Out-Null
        $date = $date.AddDays(1)
    }

    return @($dates | ForEach-Object { $_ })
}

function Add-WazuhDatedSourcePaths {
    param(
        [System.Collections.Generic.List[string]]$Paths,
        [ValidateSet("Archive", "Alert")]
        [string]$Kind,
        [DateTime]$Date
    )

    $year = $Date.ToString("yyyy", [System.Globalization.CultureInfo]::InvariantCulture)
    $month = $Date.ToString("MMM", [System.Globalization.CultureInfo]::InvariantCulture)
    $day = $Date.ToString("dd", [System.Globalization.CultureInfo]::InvariantCulture)

    if ($Kind -eq "Archive") {
        $Paths.Add("/var/ossec/logs/archives/$year/$month/ossec-archive-$day.json") | Out-Null
        $Paths.Add("/var/ossec/logs/archives/$year/$month/ossec-archive-$day.json.gz") | Out-Null
    }
    else {
        $Paths.Add("/var/ossec/logs/alerts/$year/$month/ossec-alerts-$day.json") | Out-Null
        $Paths.Add("/var/ossec/logs/alerts/$year/$month/ossec-alerts-$day.json.gz") | Out-Null
    }
}

function Get-DatedSourcePaths {
    param(
        [ValidateSet("Archive", "Alert")]
        [string]$Kind,
        [DateTimeOffset]$WindowStartUtc,
        [DateTimeOffset]$WindowEndUtc,
        [TimeSpan]$WazuhLocalOffset
    )

    $paths = New-Object System.Collections.Generic.List[string]
    $utcDates = @(Get-UtcDatesInWindow -WindowStartUtc $WindowStartUtc -WindowEndUtc $WindowEndUtc)
    $wazuhLocalDates = @(Get-OffsetDatesInWindow -WindowStartUtc $WindowStartUtc -WindowEndUtc $WindowEndUtc -Offset $WazuhLocalOffset)

    foreach ($date in $utcDates) {
        Add-WazuhDatedSourcePaths -Paths $paths -Kind $Kind -Date $date
    }
    foreach ($date in $wazuhLocalDates) {
        Add-WazuhDatedSourcePaths -Paths $paths -Kind $Kind -Date $date
    }

    return @($paths | Select-Object -Unique)
}

function Cache-RemoteJsonSources {
    param(
        [string]$Instance,
        [string]$Category,
        [string[]]$CandidatePaths,
        [string]$RemoteCacheDir,
        [string]$LocalCacheDir
    )

    $results = New-Object System.Collections.Generic.List[object]
    $sourceIndex = 0

    New-Item -ItemType Directory -Force -Path $LocalCacheDir | Out-Null

    Write-Step "Preparing Wazuh remote cache directory: $RemoteCacheDir"
    & multipass exec $Instance -- sudo mkdir -p $RemoteCacheDir 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[FAIL] Could not create remote cache directory: $RemoteCacheDir" -ForegroundColor Red
        return @()
    }

    foreach ($remotePath in @($CandidatePaths | Select-Object -Unique)) {
        Write-Step "Testing Wazuh $Category candidate: $remotePath"
        $testOutput = @(& multipass exec $Instance -- sudo test -r $remotePath 2>&1)
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[MISS] Not readable or not found: $remotePath" -ForegroundColor DarkYellow
            if ($testOutput.Count -gt 0) {
                Write-Host "Reason: $($testOutput -join ' ')" -ForegroundColor DarkYellow
            }
            continue
        }

        $sourceIndex++
        $sourceName = @($remotePath -split "/")[-1]
        if ($sourceName.EndsWith(".json.gz", [System.StringComparison]::OrdinalIgnoreCase)) {
            $sourceName = $sourceName.Substring(0, $sourceName.Length - 3)
        }
        $cacheName = "{0}-{1:D2}-{2}" -f $Category, $sourceIndex, $sourceName
        $remoteCachePath = "$RemoteCacheDir/$cacheName"
        $localCachePath = Join-Path $LocalCacheDir $cacheName

        Write-Step "Copying Wazuh $Category source: $remotePath"
        Write-Host "Remote temp: $Instance`:$remoteCachePath"

        if ($remotePath.EndsWith(".json.gz", [System.StringComparison]::OrdinalIgnoreCase)) {
            $quotedRemotePath = Convert-ToShellSingleQuoted -Value $remotePath
            $quotedRemoteCachePath = Convert-ToShellSingleQuoted -Value $remoteCachePath
            $copyOutput = @(& multipass exec $Instance -- sudo sh -c "gzip -dc $quotedRemotePath > $quotedRemoteCachePath" 2>&1)
            if ($LASTEXITCODE -ne 0) {
                Write-Host "[WARN] Could not decompress remote source: $remotePath" -ForegroundColor Yellow
                Write-Host "Reason: $($copyOutput -join ' ')" -ForegroundColor Yellow
                continue
            }
            Write-Host "[PASS] Remote gzip source decompressed: $remotePath -> $remoteCachePath" -ForegroundColor Green
        }
        else {
            $copyOutput = @(& multipass exec $Instance -- sudo cp $remotePath $remoteCachePath 2>&1)
            if ($LASTEXITCODE -ne 0) {
                Write-Host "[WARN] Could not copy remote source: $remotePath" -ForegroundColor Yellow
                Write-Host "Reason: $($copyOutput -join ' ')" -ForegroundColor Yellow
                continue
            }
            Write-Host "[PASS] Remote file copied: $remotePath -> $remoteCachePath" -ForegroundColor Green
        }

        $chmodOutput = @(& multipass exec $Instance -- sudo chmod 644 $remoteCachePath 2>&1)
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[WARN] Could not make remote temp file readable: $remoteCachePath" -ForegroundColor Yellow
            Write-Host "Reason: $($chmodOutput -join ' ')" -ForegroundColor Yellow
            continue
        }

        Remove-Item -Path $localCachePath -Force -ErrorAction SilentlyContinue
        $remoteSpec = "${Instance}:$remoteCachePath"
        Write-Step "Transferring Wazuh $Category cache to: $localCachePath"
        $transferOutput = @(& multipass transfer $remoteSpec $localCachePath 2>&1)
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -Path $localCachePath)) {
            Write-Host "[WARN] Could not transfer remote temp file: $remoteSpec" -ForegroundColor Yellow
            Write-Host "Reason: $($transferOutput -join ' ')" -ForegroundColor Yellow
            continue
        }

        $lines = @(Get-Content -Path $localCachePath -ErrorAction Stop)
        Write-Host "[PASS] Local cache created: $localCachePath" -ForegroundColor Green
        Write-Host "Lines read from local cache: $($lines.Count)"

        $results.Add([PSCustomObject]@{
            Path = $remotePath
            LocalCachePath = $localCachePath
            Lines = @($lines | ForEach-Object { [string]$_ })
        }) | Out-Null
    }

    return @($results | ForEach-Object { $_ })
}

function Select-WazuhEvents {
    param(
        [object[]]$Sources,
        [DateTimeOffset]$WindowStartUtc,
        [DateTimeOffset]$WindowEndUtc,
        [string]$Category
    )

    $selected = New-Object System.Collections.Generic.List[object]
    $seenLines = New-Object "System.Collections.Generic.HashSet[string]"
    $invalidJsonCount = 0
    $missingTimestampCount = 0

    foreach ($source in $Sources) {
        foreach ($line in @($source.Lines)) {
            if ([string]::IsNullOrWhiteSpace($line) -or -not $seenLines.Add($line)) {
                continue
            }

            try {
                $event = $line | ConvertFrom-Json -ErrorAction Stop
            }
            catch {
                $invalidJsonCount++
                continue
            }

            $timestampUtc = Get-WazuhTimestampUtc -Event $event
            if (-not $timestampUtc) {
                $missingTimestampCount++
                continue
            }

            if ($timestampUtc -ge $WindowStartUtc -and $timestampUtc -le $WindowEndUtc) {
                $selected.Add([PSCustomObject]@{
                    Raw = $line
                    Event = $event
                    TimestampUtc = $timestampUtc
                    SourcePath = $source.Path
                }) | Out-Null
            }
        }
    }

    if ($invalidJsonCount -gt 0) {
        Write-Host "[WARN] $Category sources contained $invalidJsonCount invalid JSON line(s)." -ForegroundColor Yellow
    }
    if ($missingTimestampCount -gt 0) {
        Write-Host "[WARN] $Category sources contained $missingTimestampCount JSON line(s) without a parseable timestamp." -ForegroundColor Yellow
    }

    return @($selected | Sort-Object TimestampUtc)
}

function Add-Count {
    param(
        [hashtable]$Counts,
        [object]$Value
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return
    }

    $key = [string]$Value
    if ($Counts.ContainsKey($key)) {
        $Counts[$key]++
    }
    else {
        $Counts[$key] = 1
    }
}

function Convert-ToOrderedCounts {
    param([hashtable]$Counts)

    $ordered = [ordered]@{}
    foreach ($key in @($Counts.Keys | Sort-Object)) {
        $ordered[$key] = $Counts[$key]
    }

    return $ordered
}

function Get-AgentCounts {
    param([object[]]$Entries)

    $counts = @{}
    foreach ($entry in $Entries) {
        $value = Get-NestedValue -Object $entry.Event -Path @("agent", "name")
        if (-not $value) {
            $value = Get-NestedValue -Object $entry.Event -Path @("agent", "id")
        }
        if (-not $value) {
            $value = "unknown"
        }
        Add-Count -Counts $counts -Value $value
    }

    return Convert-ToOrderedCounts -Counts $counts
}

function Get-NestedCounts {
    param(
        [object[]]$Entries,
        [string[]]$Path
    )

    $counts = @{}
    foreach ($entry in $Entries) {
        foreach ($value in @(Get-NestedValue -Object $entry.Event -Path $Path)) {
            Add-Count -Counts $counts -Value $value
        }
    }

    return Convert-ToOrderedCounts -Counts $counts
}

function Write-RawJsonLines {
    param(
        [object[]]$Entries,
        [string]$Path
    )

    $lines = @($Entries | ForEach-Object { [string]$_.Raw })
    if ($lines.Count -eq 0) {
        New-Item -ItemType File -Force -Path $Path | Out-Null
        Clear-Content -Path $Path
        return
    }

    Set-Content -Path $Path -Value $lines -Encoding UTF8
}

function Write-JsonFile {
    param(
        [object]$Value,
        [string]$Path,
        [int]$Depth = 20
    )

    $Value | ConvertTo-Json -Depth $Depth | Set-Content -Path $Path -Encoding UTF8
}

Write-Host "============================================================"
Write-Host "Coding Fest 2026 XDR Wazuh Evidence Export"
Write-Host "============================================================"
Write-Host "Metadata:           $MetadataPath"
Write-Host "OutputRoot:         $OutputRoot"
Write-Host "TimePaddingSeconds: $TimePaddingSeconds"
Write-Host "WazuhInstance:      $WazuhInstance"

if (-not (Test-Path -Path $MetadataPath)) {
    Write-Host "Metadata file not found: $MetadataPath" -ForegroundColor Red
    exit 1
}

try {
    $metadata = Get-Content -Raw -Path $MetadataPath | ConvertFrom-Json -ErrorAction Stop
}
catch {
    Write-Host "Failed to parse metadata JSON: $MetadataPath" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

$runId = [string](Get-FirstObjectValue -Object $metadata -Names @("run_id") -Default "")
$startValue = [string](Get-FirstObjectValue -Object $metadata -Names @("started_utc", "start_time_utc") -Default "")
$endValue = [string](Get-FirstObjectValue -Object $metadata -Names @("ended_utc", "end_time_utc") -Default "")
$label = [string](Get-FirstObjectValue -Object $metadata -Names @("label", "main_label") -Default "")

if ([string]::IsNullOrWhiteSpace($runId)) {
    Write-Host "Metadata is missing run_id." -ForegroundColor Red
    exit 1
}

$startTimeUtc = Convert-ToUtcDateTimeOffset -Value $startValue
$endTimeUtc = Convert-ToUtcDateTimeOffset -Value $endValue
if (-not $startTimeUtc -or -not $endTimeUtc) {
    Write-Host "Metadata is missing parseable started_utc/start_time_utc or ended_utc/end_time_utc." -ForegroundColor Red
    exit 1
}
if ($endTimeUtc -lt $startTimeUtc) {
    Write-Host "Metadata end time occurs before start time." -ForegroundColor Red
    exit 1
}

$safeRunId = $runId -replace '[^A-Za-z0-9._-]', '_'
$windowStartUtc = $startTimeUtc.AddSeconds(-1 * $TimePaddingSeconds)
$windowEndUtc = $endTimeUtc.AddSeconds($TimePaddingSeconds)
$remoteCacheDir = "/tmp/xdr-wazuh-export/$safeRunId"
$localCacheDir = Join-Path "exports\wazuh-cache" $safeRunId

Write-Host "RunId:              $runId"
Write-Host "Window UTC:         $($windowStartUtc.ToString('o')) to $($windowEndUtc.ToString('o'))"
Write-Host "Wazuh log offset:   $($WazuhLogTimeZoneOffset.ToString())"
Write-Host "Local Wazuh cache:  $localCacheDir"

Write-Step "Checking Multipass access to $WazuhInstance"
if (-not (Test-MultipassInstance -Instance $WazuhInstance)) {
    Write-Host "Cannot connect to Multipass instance '$WazuhInstance'." -ForegroundColor Red
    exit 1
}

$archiveCandidates = @(@($CurrentArchivePath) + @(Get-DatedSourcePaths -Kind Archive -WindowStartUtc $windowStartUtc -WindowEndUtc $windowEndUtc -WazuhLocalOffset $WazuhLogTimeZoneOffset) | Select-Object -Unique)
$alertCandidates = @(@($CurrentAlertPath) + @(Get-DatedSourcePaths -Kind Alert -WindowStartUtc $windowStartUtc -WindowEndUtc $windowEndUtc -WazuhLocalOffset $WazuhLogTimeZoneOffset) | Select-Object -Unique)

$archiveSources = @(Cache-RemoteJsonSources -Instance $WazuhInstance -Category "archive" -CandidatePaths $archiveCandidates -RemoteCacheDir $remoteCacheDir -LocalCacheDir $localCacheDir)
$alertSources = @(Cache-RemoteJsonSources -Instance $WazuhInstance -Category "alert" -CandidatePaths $alertCandidates -RemoteCacheDir $remoteCacheDir -LocalCacheDir $localCacheDir)

if ($archiveSources.Count -eq 0) {
    Write-Host "No readable Wazuh archive JSON source was found for the evidence window." -ForegroundColor Red
    exit 1
}
if ($alertSources.Count -eq 0) {
    Write-Host "[WARN] No readable Wazuh alert JSON source was found. The alert slice will be empty." -ForegroundColor Yellow
}

Write-Step "Filtering Wazuh evidence to the run window"
$archiveEvents = @(Select-WazuhEvents -Sources $archiveSources -WindowStartUtc $windowStartUtc -WindowEndUtc $windowEndUtc -Category "archive")
$alertEvents = @(Select-WazuhEvents -Sources $alertSources -WindowStartUtc $windowStartUtc -WindowEndUtc $windowEndUtc -Category "alert")

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$outputDir = Join-Path $OutputRoot $safeRunId
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$archivesOut = Join-Path $outputDir "wazuh-archives-slice.json"
$alertsOut = Join-Path $outputDir "wazuh-alerts-slice.json"
$summaryOut = Join-Path $outputDir "wazuh-evidence-summary.json"
$manifestPath = Join-Path $outputDir "manifest.json"
$exportedAtUtc = [DateTimeOffset]::UtcNow.ToString("o")

$summary = [ordered]@{
    run_id = $runId
    scenario = [string](Get-FirstObjectValue -Object $metadata -Names @("scenario") -Default "")
    label = $label
    sublabel = [string](Get-FirstObjectValue -Object $metadata -Names @("sublabel") -Default "")
    scenario_variant = [string](Get-FirstObjectValue -Object $metadata -Names @("scenario_variant") -Default "")
    actor_profile = [string](Get-FirstObjectValue -Object $metadata -Names @("actor_profile") -Default "")
    intensity = [string](Get-FirstObjectValue -Object $metadata -Names @("intensity") -Default "")
    benign_activity_level = [string](Get-FirstObjectValue -Object $metadata -Names @("benign_activity_level") -Default "")
    generator_version = [string](Get-FirstObjectValue -Object $metadata -Names @("generator_version") -Default "")
    planned_request_count = Get-FirstObjectValue -Object $metadata -Names @("planned_request_count") -Default $null
    actual_request_count = Get-FirstObjectValue -Object $metadata -Names @("actual_request_count") -Default $null
    safety_limit_applied = Get-FirstObjectValue -Object $metadata -Names @("safety_limit_applied") -Default $null
    target_endpoint_family = [string](Get-FirstObjectValue -Object $metadata -Names @("target_endpoint_family") -Default "")
    window_start_utc = $windowStartUtc.ToString("o")
    window_end_utc = $windowEndUtc.ToString("o")
    archive_event_count = $archiveEvents.Count
    alert_event_count = $alertEvents.Count
    archive_agent_counts = Get-AgentCounts -Entries $archiveEvents
    alert_agent_counts = Get-AgentCounts -Entries $alertEvents
    archive_location_counts = Get-NestedCounts -Entries $archiveEvents -Path @("location")
    alert_rule_id_counts = Get-NestedCounts -Entries $alertEvents -Path @("rule", "id")
    alert_rule_level_counts = Get-NestedCounts -Entries $alertEvents -Path @("rule", "level")
    alert_rule_group_counts = Get-NestedCounts -Entries $alertEvents -Path @("rule", "groups")
    alert_mitre_id_counts = Get-NestedCounts -Entries $alertEvents -Path @("rule", "mitre", "id")
    decoder_counts = Get-NestedCounts -Entries $archiveEvents -Path @("decoder", "name")
    generated_at_utc = $exportedAtUtc
}

Write-Step "Writing Wazuh evidence files"
Write-RawJsonLines -Entries $archiveEvents -Path $archivesOut
Write-RawJsonLines -Entries $alertEvents -Path $alertsOut
Write-JsonFile -Value $summary -Path $summaryOut

if (Test-Path -Path $manifestPath) {
    Write-Step "Updating existing verified-run manifest"
    try {
        $manifest = Get-Content -Raw -Path $manifestPath | ConvertFrom-Json -ErrorAction Stop
        $wazuhEvidence = [ordered]@{
            archives_slice_path = $archivesOut
            alerts_slice_path = $alertsOut
            summary_path = $summaryOut
            archive_event_count = $archiveEvents.Count
            alert_event_count = $alertEvents.Count
            exported_at_utc = $exportedAtUtc
        }
        $manifest | Add-Member -NotePropertyName "wazuh_evidence" -NotePropertyValue $wazuhEvidence -Force
        Write-JsonFile -Value $manifest -Path $manifestPath
    }
    catch {
        Write-Host "Failed to update manifest: $manifestPath" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "[WARN] Existing manifest not found; Wazuh files were written without a manifest update: $manifestPath" -ForegroundColor Yellow
}

Write-Host "`n============================================================"
Write-Host "SUMMARY"
Write-Host "============================================================"
Write-Host "RunId:              $runId"
Write-Host "Archive event count: $($archiveEvents.Count)"
Write-Host "Alert event count:   $($alertEvents.Count)"
if ($label -ne "Benign" -and $archiveEvents.Count -eq 0) {
    Write-Host "[WARN] Attack-labelled run exported zero Wazuh archive events; do not treat this as validated evidence." -ForegroundColor Yellow
}
Write-Host "Archives slice:      $archivesOut"
Write-Host "Alerts slice:        $alertsOut"
Write-Host "Evidence summary:    $summaryOut"
Write-Host "Wazuh evidence export completed." -ForegroundColor Green
exit 0
