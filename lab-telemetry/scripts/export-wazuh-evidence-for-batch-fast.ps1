# export-wazuh-evidence-for-batch-fast.ps1
# Exports Wazuh evidence for a batch by copying each required Wazuh source once,
# then filtering all per-run windows locally.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BatchManifestPath,

    [ValidateRange(0, 3600)]
    [int]$TimePaddingSeconds = 10,

    [string]$WazuhInstance = "wazuh-server",

    [switch]$IncludeBenign,

    [switch]$ReExportZeroArchive,

    [switch]$ReExportMissing = $true,

    [switch]$PlanOnly,

    [int]$MaxRuns = 0
)

$ErrorActionPreference = "Continue"

$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Join-Path (Get-Location) "scripts" }
$RepoRoot = Split-Path -Path $ScriptRoot -Parent
$VerifiedRunsRootRelative = "exports\verified-runs"
$VerifiedRunsRoot = Join-Path $RepoRoot $VerifiedRunsRootRelative
$WazuhCacheRoot = Join-Path $RepoRoot "exports\wazuh-cache"
$CurrentArchivePath = "/var/ossec/logs/archives/archives.json"
$CurrentAlertPath = "/var/ossec/logs/alerts/alerts.json"
$RemoteCacheDir = "/tmp/xdr-wazuh-export/batch-cache"
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

    foreach ($path in @(
        @("data", "timestamp"),
        @("data", "@timestamp"),
        @("data", "time"),
        @("data", "created_at"),
        @("data", "event_time")
    )) {
        $value = Get-NestedValue -Object $Event -Path $path
        if ($value) {
            $parsed = Convert-ToUtcDateTimeOffset -Value ([string]$value)
            if ($parsed) {
                return $parsed
            }
        }
    }

    $dataValue = Get-ObjectValue -Object $Event -Name "data" -Default $null
    if ($dataValue -is [string] -and -not [string]::IsNullOrWhiteSpace($dataValue)) {
        $trimmed = $dataValue.Trim()
        if ($trimmed.StartsWith("{") -and $trimmed.EndsWith("}")) {
            try {
                $embedded = $trimmed | ConvertFrom-Json -ErrorAction Stop
                foreach ($field in @("timestamp", "@timestamp", "time", "created_at", "event_time")) {
                    $value = Get-ObjectValue -Object $embedded -Name $field -Default $null
                    if ($value) {
                        $parsed = Convert-ToUtcDateTimeOffset -Value ([string]$value)
                        if ($parsed) {
                            return $parsed
                        }
                    }
                }
            }
            catch {
                return $null
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

function Resolve-MetadataPath {
    param([object]$Run)

    $metadataPath = [string]$Run.metadata_path
    if (-not [string]::IsNullOrWhiteSpace($metadataPath) -and (Test-Path -Path $metadataPath)) {
        return $metadataPath
    }

    $fallback = Join-Path (Join-Path $RepoRoot "exports") "$($Run.run_id)-metadata.json"
    if (Test-Path -Path $fallback) {
        return $fallback
    }

    return $metadataPath
}

function Resolve-ExportPath {
    param([object]$Run)

    $exportPath = [string]$Run.export_path
    if (-not [string]::IsNullOrWhiteSpace($exportPath)) {
        return $exportPath
    }

    $safeRunId = ([string]$Run.run_id) -replace '[^A-Za-z0-9._-]', '_'
    return (Join-Path $VerifiedRunsRoot $safeRunId)
}

function Get-SummaryArchiveCount {
    param([string]$SummaryPath)

    if (-not (Test-Path -Path $SummaryPath)) {
        return $null
    }

    try {
        $summary = Get-Content -Raw -Path $SummaryPath | ConvertFrom-Json -ErrorAction Stop
        return $summary.archive_event_count
    }
    catch {
        return $null
    }
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

function Initialize-RemoteBatchCache {
    param(
        [string]$Instance,
        [string]$RemoteDir
    )

    Write-Step "Cleaning remote batch temp cache: $RemoteDir"
    $removeOutput = @(& multipass exec $Instance -- sudo rm -rf $RemoteDir 2>&1)
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[FAIL] Could not clean remote batch temp cache: $RemoteDir" -ForegroundColor Red
        Write-Host "Reason: $($removeOutput -join ' ')" -ForegroundColor Red
        return $false
    }

    $mkdirOutput = @(& multipass exec $Instance -- sudo mkdir -p $RemoteDir 2>&1)
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[FAIL] Could not create remote batch temp cache: $RemoteDir" -ForegroundColor Red
        Write-Host "Reason: $($mkdirOutput -join ' ')" -ForegroundColor Red
        return $false
    }

    return $true
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

        Write-Step "Copying Wazuh $Category source once: $remotePath"
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
            $operation = "decompressed"
            Write-Host "[PASS] Remote gzip source decompressed: $remotePath -> $remoteCachePath" -ForegroundColor Green
        }
        else {
            $copyOutput = @(& multipass exec $Instance -- sudo cp $remotePath $remoteCachePath 2>&1)
            if ($LASTEXITCODE -ne 0) {
                Write-Host "[WARN] Could not copy remote source: $remotePath" -ForegroundColor Yellow
                Write-Host "Reason: $($copyOutput -join ' ')" -ForegroundColor Yellow
                continue
            }
            $operation = "copied"
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

        $lineCount = 0
        try {
            foreach ($unused in [System.IO.File]::ReadLines($localCachePath)) {
                $lineCount++
            }
        }
        catch {
            Write-Host "[WARN] Could not count lines in local cache: $localCachePath" -ForegroundColor Yellow
        }

        Write-Host "[PASS] Local cache created: $localCachePath" -ForegroundColor Green
        Write-Host "Lines in local cache: $lineCount"

        $results.Add([PSCustomObject]@{
            Path = $remotePath
            LocalCachePath = $localCachePath
            Operation = $operation
            LineCount = $lineCount
        }) | Out-Null
    }

    return @($results | ForEach-Object { $_ })
}

function Read-WazuhCachedEvents {
    param(
        [object[]]$Sources,
        [string]$Category
    )

    $entries = New-Object System.Collections.Generic.List[object]
    $seenLines = New-Object "System.Collections.Generic.HashSet[string]"
    $invalidJsonCount = 0
    $missingTimestampCount = 0
    $readLineCount = 0

    foreach ($source in $Sources) {
        Write-Step "Parsing cached Wazuh $Category source: $($source.LocalCachePath)"
        try {
            foreach ($line in [System.IO.File]::ReadLines($source.LocalCachePath)) {
                $readLineCount++
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

                $entries.Add([PSCustomObject]@{
                    Raw = [string]$line
                    Event = $event
                    TimestampUtc = $timestampUtc
                    SourcePath = $source.Path
                }) | Out-Null
            }
        }
        catch {
            Write-Host "[WARN] Could not read cached source: $($source.LocalCachePath)" -ForegroundColor Yellow
            Write-Host $_.Exception.Message -ForegroundColor Yellow
        }
    }

    if ($invalidJsonCount -gt 0) {
        Write-Host "[WARN] $Category sources contained $invalidJsonCount invalid JSON line(s)." -ForegroundColor Yellow
    }
    if ($missingTimestampCount -gt 0) {
        Write-Host "[WARN] $Category sources contained $missingTimestampCount JSON line(s) without a parseable timestamp." -ForegroundColor Yellow
    }

    Write-Host "Parsed $($entries.Count) unique timestamped $Category event(s) from $readLineCount cached line(s)."
    return @($entries | Sort-Object TimestampUtc)
}

function Select-CachedWazuhEvents {
    param(
        [object[]]$Entries,
        [DateTimeOffset]$WindowStartUtc,
        [DateTimeOffset]$WindowEndUtc
    )

    return @($Entries | Where-Object {
        $_.TimestampUtc -ge $WindowStartUtc -and $_.TimestampUtc -le $WindowEndUtc
    } | Sort-Object TimestampUtc)
}

function New-RunSummary {
    param(
        [object]$Metadata,
        [string]$RunId,
        [object[]]$ArchiveEvents,
        [object[]]$AlertEvents,
        [DateTimeOffset]$WindowStartUtc,
        [DateTimeOffset]$WindowEndUtc,
        [string]$ExportedAtUtc
    )

    return [ordered]@{
        run_id = $RunId
        scenario = [string](Get-FirstObjectValue -Object $Metadata -Names @("scenario") -Default "")
        label = [string](Get-FirstObjectValue -Object $Metadata -Names @("label", "main_label") -Default "")
        sublabel = [string](Get-FirstObjectValue -Object $Metadata -Names @("sublabel") -Default "")
        scenario_variant = [string](Get-FirstObjectValue -Object $Metadata -Names @("scenario_variant") -Default "")
        actor_profile = [string](Get-FirstObjectValue -Object $Metadata -Names @("actor_profile") -Default "")
        intensity = [string](Get-FirstObjectValue -Object $Metadata -Names @("intensity") -Default "")
        benign_activity_level = [string](Get-FirstObjectValue -Object $Metadata -Names @("benign_activity_level") -Default "")
        generator_version = [string](Get-FirstObjectValue -Object $Metadata -Names @("generator_version") -Default "")
        planned_request_count = Get-FirstObjectValue -Object $Metadata -Names @("planned_request_count") -Default $null
        actual_request_count = Get-FirstObjectValue -Object $Metadata -Names @("actual_request_count") -Default $null
        safety_limit_applied = Get-FirstObjectValue -Object $Metadata -Names @("safety_limit_applied") -Default $null
        target_endpoint_family = [string](Get-FirstObjectValue -Object $Metadata -Names @("target_endpoint_family") -Default "")
        window_start_utc = $WindowStartUtc.ToString("o")
        window_end_utc = $WindowEndUtc.ToString("o")
        archive_event_count = $ArchiveEvents.Count
        alert_event_count = $AlertEvents.Count
        archive_agent_counts = Get-AgentCounts -Entries $ArchiveEvents
        alert_agent_counts = Get-AgentCounts -Entries $AlertEvents
        archive_location_counts = Get-NestedCounts -Entries $ArchiveEvents -Path @("location")
        alert_rule_id_counts = Get-NestedCounts -Entries $AlertEvents -Path @("rule", "id")
        alert_rule_level_counts = Get-NestedCounts -Entries $AlertEvents -Path @("rule", "level")
        alert_rule_group_counts = Get-NestedCounts -Entries $AlertEvents -Path @("rule", "groups")
        alert_mitre_id_counts = Get-NestedCounts -Entries $AlertEvents -Path @("rule", "mitre", "id")
        decoder_counts = Get-NestedCounts -Entries $ArchiveEvents -Path @("decoder", "name")
        generated_at_utc = $ExportedAtUtc
    }
}

function Update-VerifiedRunManifest {
    param(
        [string]$ManifestPath,
        [string]$ArchivesPathForManifest,
        [string]$AlertsPathForManifest,
        [string]$SummaryPathForManifest,
        [int]$ArchiveCount,
        [int]$AlertCount,
        [string]$ExportedAtUtc
    )

    if (-not (Test-Path -Path $ManifestPath)) {
        Write-Host "[WARN] Existing manifest not found; Wazuh files were written without a manifest update: $ManifestPath" -ForegroundColor Yellow
        return $true
    }

    try {
        $manifest = Get-Content -Raw -Path $ManifestPath | ConvertFrom-Json -ErrorAction Stop
        $wazuhEvidence = [ordered]@{
            archives_slice_path = $ArchivesPathForManifest
            alerts_slice_path = $AlertsPathForManifest
            summary_path = $SummaryPathForManifest
            archive_event_count = $ArchiveCount
            alert_event_count = $AlertCount
            exported_at_utc = $ExportedAtUtc
        }
        $manifest | Add-Member -NotePropertyName "wazuh_evidence" -NotePropertyValue $wazuhEvidence -Force
        Write-JsonFile -Value $manifest -Path $ManifestPath
        return $true
    }
    catch {
        Write-Host "[FAIL] Failed to update manifest: $ManifestPath" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        return $false
    }
}

Write-Host "============================================================"
Write-Host "Coding Fest 2026 XDR Fast Batch Wazuh Evidence Export"
Write-Host "============================================================"
Write-Host "BatchManifestPath:   $BatchManifestPath"
Write-Host "TimePaddingSeconds:  $TimePaddingSeconds"
Write-Host "WazuhInstance:       $WazuhInstance"
Write-Host "IncludeBenign:       $($IncludeBenign.IsPresent)"
Write-Host "ReExportMissing:     $($ReExportMissing.IsPresent)"
Write-Host "ReExportZeroArchive: $($ReExportZeroArchive.IsPresent)"
Write-Host "PlanOnly:            $($PlanOnly.IsPresent)"
if ($MaxRuns -gt 0) {
    Write-Host "MaxRuns:             $MaxRuns"
}

if (-not (Test-Path -Path $BatchManifestPath)) {
    Write-Host "Batch manifest not found: $BatchManifestPath" -ForegroundColor Red
    exit 1
}

try {
    $batch = Get-Content -Raw -Path $BatchManifestPath | ConvertFrom-Json -ErrorAction Stop
}
catch {
    Write-Host "Failed to parse batch manifest JSON: $BatchManifestPath" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

$batchId = [string](Get-FirstObjectValue -Object $batch -Names @("batch_id") -Default ([System.IO.Path]::GetFileNameWithoutExtension($BatchManifestPath)))
$safeBatchId = $batchId -replace '[^A-Za-z0-9._-]', '_'
$localBatchCacheDir = Join-Path $WazuhCacheRoot "batch-$safeBatchId"

$candidateRuns = @($batch.runs | Where-Object {
    ([string]$_.status -eq "completed") -and
    ([string]$_.verification_status -eq "passed") -and
    ([string]$_.export_status -eq "exported")
})

if (-not $IncludeBenign.IsPresent) {
    $candidateRuns = @($candidateRuns | Where-Object {
        $label = [string](Get-FirstObjectValue -Object $_ -Names @("label", "main_label", "scenario") -Default "")
        $label -ne "Benign"
    })
}

$selectedRuns = New-Object System.Collections.Generic.List[object]
foreach ($run in $candidateRuns) {
    $runId = [string]$run.run_id
    $safeRunId = $runId -replace '[^A-Za-z0-9._-]', '_'
    $exportPath = Resolve-ExportPath -Run $run
    $summaryPath = Join-Path $exportPath "wazuh-evidence-summary.json"
    $summaryExists = Test-Path -Path $summaryPath
    $archiveCount = Get-SummaryArchiveCount -SummaryPath $summaryPath
    $needsMissingExport = $ReExportMissing.IsPresent -and (-not $summaryExists)
    $needsZeroReExport = $ReExportZeroArchive.IsPresent -and $summaryExists -and ($archiveCount -eq 0)

    if (-not $needsMissingExport -and -not $needsZeroReExport) {
        continue
    }

    $metadataPath = Resolve-MetadataPath -Run $run
    $selectedRuns.Add([PSCustomObject]@{
        Run = $run
        RunId = $runId
        SafeRunId = $safeRunId
        Label = [string](Get-FirstObjectValue -Object $run -Names @("label", "main_label", "scenario") -Default "")
        MetadataPath = $metadataPath
        ExportPath = $exportPath
        SummaryPath = $summaryPath
        SelectionReason = if ($needsMissingExport) { "missing_wazuh_summary" } else { "zero_archive_event_count" }
    }) | Out-Null
}

$selectedRuns = @($selectedRuns | Sort-Object { $_.Run.sequence }, RunId)
if ($MaxRuns -gt 0) {
    $selectedRuns = @($selectedRuns | Select-Object -First $MaxRuns)
}

if ($selectedRuns.Count -eq 0) {
    Write-Host "No target runs matched the requested export criteria." -ForegroundColor Yellow
    exit 0
}

$targets = New-Object System.Collections.Generic.List[object]
$loadFailures = New-Object System.Collections.Generic.List[object]
foreach ($selected in $selectedRuns) {
    if ([string]::IsNullOrWhiteSpace($selected.MetadataPath) -or -not (Test-Path -Path $selected.MetadataPath)) {
        $loadFailures.Add([PSCustomObject]@{
            RunId = $selected.RunId
            Status = "FAIL"
            ArchiveEvents = $null
            AlertEvents = $null
            Details = "metadata not found"
        }) | Out-Null
        continue
    }

    try {
        $metadata = Get-Content -Raw -Path $selected.MetadataPath | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        $loadFailures.Add([PSCustomObject]@{
            RunId = $selected.RunId
            Status = "FAIL"
            ArchiveEvents = $null
            AlertEvents = $null
            Details = "metadata parse failed"
        }) | Out-Null
        continue
    }

    $startValue = [string](Get-FirstObjectValue -Object $metadata -Names @("started_utc", "start_time_utc") -Default "")
    $endValue = [string](Get-FirstObjectValue -Object $metadata -Names @("ended_utc", "end_time_utc") -Default "")
    $startTimeUtc = Convert-ToUtcDateTimeOffset -Value $startValue
    $endTimeUtc = Convert-ToUtcDateTimeOffset -Value $endValue
    if (-not $startTimeUtc -or -not $endTimeUtc -or $endTimeUtc -lt $startTimeUtc) {
        $loadFailures.Add([PSCustomObject]@{
            RunId = $selected.RunId
            Status = "FAIL"
            ArchiveEvents = $null
            AlertEvents = $null
            Details = "missing or invalid run time window"
        }) | Out-Null
        continue
    }

    $windowStartUtc = $startTimeUtc.AddSeconds(-1 * $TimePaddingSeconds)
    $windowEndUtc = $endTimeUtc.AddSeconds($TimePaddingSeconds)
    $label = [string](Get-FirstObjectValue -Object $metadata -Names @("label", "main_label") -Default $selected.Label)

    $targets.Add([PSCustomObject]@{
        RunId = $selected.RunId
        SafeRunId = $selected.SafeRunId
        Label = $label
        Metadata = $metadata
        MetadataPath = $selected.MetadataPath
        ExportPath = $selected.ExportPath
        WindowStartUtc = $windowStartUtc
        WindowEndUtc = $windowEndUtc
        SelectionReason = $selected.SelectionReason
    }) | Out-Null
}

$archivePathList = New-Object System.Collections.Generic.List[string]
$alertPathList = New-Object System.Collections.Generic.List[string]
$archivePathList.Add($CurrentArchivePath) | Out-Null
$alertPathList.Add($CurrentAlertPath) | Out-Null

foreach ($target in $targets) {
    foreach ($path in @(Get-DatedSourcePaths -Kind Archive -WindowStartUtc $target.WindowStartUtc -WindowEndUtc $target.WindowEndUtc -WazuhLocalOffset $WazuhLogTimeZoneOffset)) {
        $archivePathList.Add($path) | Out-Null
    }
    foreach ($path in @(Get-DatedSourcePaths -Kind Alert -WindowStartUtc $target.WindowStartUtc -WindowEndUtc $target.WindowEndUtc -WazuhLocalOffset $WazuhLogTimeZoneOffset)) {
        $alertPathList.Add($path) | Out-Null
    }
}

$archiveCandidates = @($archivePathList | Select-Object -Unique)
$alertCandidates = @($alertPathList | Select-Object -Unique)

Write-Host "`n============================================================"
Write-Host "PLAN"
Write-Host "============================================================"
Write-Host "BatchId:              $batchId"
Write-Host "Candidate runs:       $($candidateRuns.Count)"
Write-Host "Target run count:     $($targets.Count)"
Write-Host "Selection load fails: $($loadFailures.Count)"
Write-Host "Archive sources needed: $($archiveCandidates.Count)"
Write-Host "Alert sources needed:   $($alertCandidates.Count)"
Write-Host "Local batch cache:    $localBatchCacheDir"
Write-Host "Remote temp cache:    $RemoteCacheDir"

Write-Host "`nTarget runs:"
$targetPreviewLimit = if ($MaxRuns -gt 0) { $targets.Count } else { 25 }
@($targets | Select-Object -First $targetPreviewLimit) | Select-Object RunId, Label, SelectionReason, WindowStartUtc, WindowEndUtc | Format-Table -AutoSize -Wrap
if ($targets.Count -gt $targetPreviewLimit) {
    Write-Host ("... {0} additional target run(s) omitted from preview." -f ($targets.Count - $targetPreviewLimit))
}

Write-Host "`nArchive source candidates:"
$archiveCandidates | ForEach-Object { Write-Host "  $_" }
Write-Host "`nAlert source candidates:"
$alertCandidates | ForEach-Object { Write-Host "  $_" }

if ($PlanOnly.IsPresent) {
    Write-Host "`nPlanOnly requested; no Wazuh files were copied and no run outputs were written." -ForegroundColor Yellow
    if ($loadFailures.Count -gt 0) {
        Write-Host "Runs with metadata/time-window load failures:"
        $loadFailures | Format-Table -AutoSize -Wrap
    }
    exit 0
}

if ($targets.Count -eq 0) {
    Write-Host "No target runs have loadable metadata/time windows." -ForegroundColor Red
    exit 1
}

Write-Step "Checking Multipass access to $WazuhInstance"
if (-not (Test-MultipassInstance -Instance $WazuhInstance)) {
    Write-Host "Cannot connect to Multipass instance '$WazuhInstance'." -ForegroundColor Red
    exit 1
}

if (-not (Initialize-RemoteBatchCache -Instance $WazuhInstance -RemoteDir $RemoteCacheDir)) {
    exit 1
}

$archiveSources = @(Cache-RemoteJsonSources -Instance $WazuhInstance -Category "archive" -CandidatePaths $archiveCandidates -RemoteCacheDir $RemoteCacheDir -LocalCacheDir $localBatchCacheDir)
$alertSources = @(Cache-RemoteJsonSources -Instance $WazuhInstance -Category "alert" -CandidatePaths $alertCandidates -RemoteCacheDir $RemoteCacheDir -LocalCacheDir $localBatchCacheDir)

Write-Host "`n============================================================"
Write-Host "SOURCE CACHE SUMMARY"
Write-Host "============================================================"
Write-Host "Archive sources copied/decompressed: $($archiveSources.Count) of $($archiveCandidates.Count)"
Write-Host "Alert sources copied/decompressed:   $($alertSources.Count) of $($alertCandidates.Count)"
$copiedSources = @($archiveSources + $alertSources)
if ($copiedSources.Count -gt 0) {
    $copiedSources | Select-Object Path, Operation, LocalCachePath, LineCount | Format-Table -AutoSize -Wrap
}

if ($archiveSources.Count -eq 0) {
    Write-Host "No readable Wazuh archive JSON source was found for the target windows." -ForegroundColor Red
    exit 1
}
if ($alertSources.Count -eq 0) {
    Write-Host "[WARN] No readable Wazuh alert JSON source was found. Alert slices will be empty." -ForegroundColor Yellow
}

$archiveCacheEvents = @(Read-WazuhCachedEvents -Sources $archiveSources -Category "archive")
$alertCacheEvents = @(Read-WazuhCachedEvents -Sources $alertSources -Category "alert")

$results = New-Object System.Collections.Generic.List[object]
foreach ($failure in $loadFailures) {
    $results.Add($failure) | Out-Null
}

foreach ($target in $targets) {
    Write-Host "`n============================================================"
    Write-Step "Filtering Wazuh evidence for $($target.RunId)"

    $archiveEvents = @(Select-CachedWazuhEvents -Entries $archiveCacheEvents -WindowStartUtc $target.WindowStartUtc -WindowEndUtc $target.WindowEndUtc)
    $alertEvents = @(Select-CachedWazuhEvents -Entries $alertCacheEvents -WindowStartUtc $target.WindowStartUtc -WindowEndUtc $target.WindowEndUtc)

    New-Item -ItemType Directory -Force -Path $target.ExportPath | Out-Null
    $archivesOut = Join-Path $target.ExportPath "wazuh-archives-slice.json"
    $alertsOut = Join-Path $target.ExportPath "wazuh-alerts-slice.json"
    $summaryOut = Join-Path $target.ExportPath "wazuh-evidence-summary.json"
    $manifestPath = Join-Path $target.ExportPath "manifest.json"
    $relativeOutputDir = Join-Path $VerifiedRunsRootRelative $target.SafeRunId
    $archivesPathForManifest = Join-Path $relativeOutputDir "wazuh-archives-slice.json"
    $alertsPathForManifest = Join-Path $relativeOutputDir "wazuh-alerts-slice.json"
    $summaryPathForManifest = Join-Path $relativeOutputDir "wazuh-evidence-summary.json"
    $exportedAtUtc = [DateTimeOffset]::UtcNow.ToString("o")

    Write-RawJsonLines -Entries $archiveEvents -Path $archivesOut
    Write-RawJsonLines -Entries $alertEvents -Path $alertsOut
    $summary = New-RunSummary -Metadata $target.Metadata -RunId $target.RunId -ArchiveEvents $archiveEvents -AlertEvents $alertEvents -WindowStartUtc $target.WindowStartUtc -WindowEndUtc $target.WindowEndUtc -ExportedAtUtc $exportedAtUtc
    Write-JsonFile -Value $summary -Path $summaryOut

    $manifestUpdated = Update-VerifiedRunManifest `
        -ManifestPath $manifestPath `
        -ArchivesPathForManifest $archivesPathForManifest `
        -AlertsPathForManifest $alertsPathForManifest `
        -SummaryPathForManifest $summaryPathForManifest `
        -ArchiveCount $archiveEvents.Count `
        -AlertCount $alertEvents.Count `
        -ExportedAtUtc $exportedAtUtc

    $status = "PASS"
    $details = $summaryPathForManifest
    if (-not $manifestUpdated) {
        $status = "FAIL"
        $details = "manifest update failed"
    }
    elseif ($target.Label -ne "Benign" -and $archiveEvents.Count -eq 0) {
        $status = "WARN"
        $details = "attack-labelled run exported zero Wazuh archive events; do not treat this as validated evidence"
        Write-Host "[WARN] $($target.RunId) exported zero Wazuh archive events; do not treat this as validated evidence." -ForegroundColor Yellow
    }

    Write-Host ("Run {0}: archive={1}, alert={2}, status={3}" -f $target.RunId, $archiveEvents.Count, $alertEvents.Count, $status)
    $results.Add([PSCustomObject]@{
        RunId = $target.RunId
        Status = $status
        ArchiveEvents = $archiveEvents.Count
        AlertEvents = $alertEvents.Count
        Details = $details
    }) | Out-Null
}

$passed = @($results | Where-Object { $_.Status -eq "PASS" }).Count
$warned = @($results | Where-Object { $_.Status -eq "WARN" }).Count
$failed = @($results | Where-Object { $_.Status -eq "FAIL" }).Count

Write-Host "`n============================================================"
Write-Host "FAST BATCH SUMMARY"
Write-Host "============================================================"
$results | Format-Table -AutoSize -Wrap
Write-Host "Target runs:                  $($targets.Count)"
Write-Host "Source files copied once:     $($copiedSources.Count)"
Write-Host "Passed:                       $passed"
Write-Host "Warn:                         $warned"
Write-Host "Failed:                       $failed"

if ($warned -gt 0) {
    Write-Host "[WARN] One or more attack-labelled runs have zero Wazuh archive events and are not fully validated." -ForegroundColor Yellow
}
if ($failed -gt 0) {
    exit 1
}

Write-Host "Fast batch Wazuh evidence export completed." -ForegroundColor Green
exit 0
