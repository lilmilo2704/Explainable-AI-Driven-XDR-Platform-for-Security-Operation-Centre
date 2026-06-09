# verify-log-output.ps1
# Read-only verifier for labelled controlled telemetry runs.
# It reads run metadata and existing lab logs; it does not generate traffic.

[CmdletBinding()]
param(
    [string]$MetadataPath = "exports/latest-run-metadata.json",
    [string]$AuthHost = "auth-server",
    [string]$WebHost = "web-server",
    [ValidateRange(0, 3600)]
    [int]$TimePaddingSeconds = 5,
    [ValidateRange(50, 50000)]
    [int]$TailLines = 1000,
    [switch]$UseLocalLogs,
    [string]$LocalAuthLogPath = "exports\log-cache\auth.log",
    [string]$LocalWebLogPath = "exports\log-cache\webapp.log",
    [string]$LocalNginxLogPath = "exports\log-cache\nginx-access.log",
    [switch]$ShowMatchedLines,
    [switch]$Strict
)

$ErrorActionPreference = "Continue"

$AuthLogPath = "/home/ubuntu/auth-lab/logs/auth.log"
$WebLogPath = "/home/ubuntu/web-lab/logs/webapp.log"
$NginxAccessLogPath = "/var/log/nginx/access.log"
$SlowReadWarningSeconds = 10

$script:CheckResults = New-Object System.Collections.Generic.List[object]

function Add-CheckResult {
    param(
        [ValidateSet("PASS", "WARN", "FAIL")]
        [string]$Status,
        [string]$Check,
        [string]$Details,
        [object[]]$MatchedLines = @()
    )

    $script:CheckResults.Add([PSCustomObject]@{
        Status = $Status
        Check = $Check
        Details = $Details
        MatchedLines = @($MatchedLines)
    }) | Out-Null
}

function Read-RemoteLog {
    param(
        [string]$HostName,
        [string]$Path,
        [switch]$UseSudo
    )

    $label = "$HostName`:$Path"
    Write-Host "Starting read: $label (tail -n $TailLines)"
    $stdoutPath = $null
    $stderrPath = $null

    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $commandText = if ($UseSudo) {
            "multipass exec $HostName -- sudo tail -n $TailLines $Path"
        }
        else {
            "multipass exec $HostName -- tail -n $TailLines $Path"
        }

        Write-Host "Command: $commandText"
        Write-Host "Running via cmd.exe with stdout/stderr redirected to local temp files."

        $stdoutPath = Join-Path $env:TEMP ("xdr-verify-stdout-{0}.log" -f ([Guid]::NewGuid().ToString("N")))
        $stderrPath = Join-Path $env:TEMP ("xdr-verify-stderr-{0}.log" -f ([Guid]::NewGuid().ToString("N")))

        if ($UseSudo) {
            $cmdText = 'multipass exec {0} -- sudo tail -n {1} {2} > "{3}" 2> "{4}"' -f $HostName, $TailLines, $Path, $stdoutPath, $stderrPath
        }
        else {
            $cmdText = 'multipass exec {0} -- tail -n {1} {2} > "{3}" 2> "{4}"' -f $HostName, $TailLines, $Path, $stdoutPath, $stderrPath
        }

        cmd.exe /d /c $cmdText
        $exitCode = $LASTEXITCODE
        $stopwatch.Stop()

        $stdoutLines = @()
        $stderrLines = @()

        if (Test-Path -Path $stdoutPath) {
            $stdoutLines = @(Get-Content -Path $stdoutPath -ErrorAction SilentlyContinue)
        }

        if (Test-Path -Path $stderrPath) {
            $stderrLines = @(Get-Content -Path $stderrPath -ErrorAction SilentlyContinue)
        }

        Remove-Item -Path $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue

        if ($stopwatch.Elapsed.TotalSeconds -gt $SlowReadWarningSeconds) {
            Add-CheckResult -Status "WARN" -Check "Slow log read: $label" -Details ("Read took {0:N1} seconds" -f $stopwatch.Elapsed.TotalSeconds)
        }

        if ($exitCode -ne 0) {
            Write-Host "Finished read: $label failed" -ForegroundColor Yellow
            return [PSCustomObject]@{
                Success = $false
                Lines = @()
                Error = ((@($stderrLines) + @($stdoutLines)) -join "`n")
            }
        }

        $lineArray = @($stdoutLines)
        Write-Host "Finished read: $label ($($lineArray.Count) line(s))"
        return [PSCustomObject]@{
            Success = $true
            Lines = $lineArray
            Error = ""
        }
    }
    catch {
        if ($stdoutPath) {
            Remove-Item -Path $stdoutPath -Force -ErrorAction SilentlyContinue
        }
        if ($stderrPath) {
            Remove-Item -Path $stderrPath -Force -ErrorAction SilentlyContinue
        }
        Write-Host "Finished read: $label failed" -ForegroundColor Yellow
        return [PSCustomObject]@{
            Success = $false
            Lines = @()
            Error = $_.Exception.Message
        }
    }
}

function Read-LocalLog {
    param(
        [string]$SourceName,
        [string]$Path
    )

    Write-Host "Starting local read: $SourceName from $Path"

    if (-not (Test-Path -Path $Path)) {
        Write-Host "Finished local read: $SourceName missing" -ForegroundColor Yellow
        return [PSCustomObject]@{
            Success = $false
            Lines = @()
            Error = "Required local cached log file not found: $Path"
        }
    }

    try {
        $lines = @(Get-Content -Path $Path -ErrorAction Stop)
        Write-Host "Finished local read: $SourceName ($($lines.Count) line(s))"
        return [PSCustomObject]@{
            Success = $true
            Lines = $lines
            Error = ""
        }
    }
    catch {
        Write-Host "Finished local read: $SourceName failed" -ForegroundColor Yellow
        return [PSCustomObject]@{
            Success = $false
            Lines = @()
            Error = $_.Exception.Message
        }
    }
}

function New-SkippedLogRead {
    param(
        [string]$HostName,
        [string]$Path,
        [string]$Reason
    )

    Write-Host "Skipping read: $HostName`:$Path ($Reason)"
    return [PSCustomObject]@{
        Success = $true
        Skipped = $true
        Lines = @()
        Error = ""
    }
}

function Test-ExpectedLogSource {
    param(
        [object]$Metadata,
        [string]$Path
    )

    $sources = @($Metadata.expected_log_sources | ForEach-Object { [string]$_ })
    if ($sources.Count -eq 0) {
        return $true
    }

    return ($sources -contains $Path)
}

function Add-LogReadCheck {
    param(
        [string]$Name,
        [object]$ReadResult
    )

    if ($ReadResult.Skipped) {
        return
    }

    if ($ReadResult.Success) {
        Add-CheckResult -Status "PASS" -Check $Name -Details "Read $($ReadResult.Lines.Count) line(s)"
    }
    else {
        Add-CheckResult -Status "FAIL" -Check $Name -Details $ReadResult.Error
    }
}

function Get-EventValue {
    param(
        [object]$Event,
        [string]$Name
    )

    if ($null -eq $Event) {
        return $null
    }

    $property = $Event.PSObject.Properties[$Name]
    if ($property) {
        return $property.Value
    }

    return $null
}

function Convert-ToUtcDateTimeOffset {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
    $parsed = [DateTimeOffset]::MinValue

    if ([DateTimeOffset]::TryParse($Value, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) {
        return $parsed.ToUniversalTime()
    }

    return $null
}

function Get-JsonEventTimestamp {
    param([object]$Event)

    foreach ($field in @("timestamp", "@timestamp", "time", "created_at", "event_time")) {
        $value = Get-EventValue -Event $Event -Name $field
        if ($value) {
            $parsed = Convert-ToUtcDateTimeOffset -Value ([string]$value)
            if ($parsed) {
                return $parsed
            }
        }
    }

    return $null
}

function Convert-JsonLogLines {
    param(
        [string[]]$Lines,
        [string]$Source
    )

    $entries = @()
    $parseFailures = 0

    foreach ($line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        try {
            $event = $line | ConvertFrom-Json -ErrorAction Stop
            $entries += [PSCustomObject]@{
                Source = $Source
                Raw = $line
                Event = $event
                TimestampUtc = Get-JsonEventTimestamp -Event $event
                ParseOk = $true
            }
        }
        catch {
            $parseFailures++
            $entries += [PSCustomObject]@{
                Source = $Source
                Raw = $line
                Event = $null
                TimestampUtc = $null
                ParseOk = $false
            }
        }
    }

    if ($parseFailures -gt 0) {
        Add-CheckResult -Status "WARN" -Check "$Source JSON parse failures" -Details "$parseFailures non-JSON or malformed line(s) ignored for JSON checks"
    }

    return @($entries)
}

function Convert-NginxAccessLines {
    param([string[]]$Lines)

    $entries = @()
    $regex = '^(?<source_ip>\S+)\s+.*?\[(?<timestamp>[^\]]+)\]\s+"(?<method>[A-Z]+)\s+(?<target>\S+)'

    foreach ($line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $timestampUtc = $null
        $method = $null
        $target = $null
        $sourceIp = $null

        $match = [regex]::Match($line, $regex)
        if ($match.Success) {
            $sourceIp = $match.Groups["source_ip"].Value
            $method = $match.Groups["method"].Value
            $target = $match.Groups["target"].Value

            $parsed = [DateTimeOffset]::MinValue
            $timestampText = $match.Groups["timestamp"].Value
            if ($timestampText -match "^(?<prefix>\d{1,2}/[A-Za-z]{3}/\d{4}:\d{2}:\d{2}:\d{2})\s+(?<sign>[+-])(?<hours>\d{2})(?<minutes>\d{2})$") {
                $timestampText = "{0} {1}{2}:{3}" -f $matches["prefix"], $matches["sign"], $matches["hours"], $matches["minutes"]
            }

            foreach ($format in @("dd/MMM/yyyy:HH:mm:ss zzz", "d/MMM/yyyy:HH:mm:ss zzz")) {
                if ([DateTimeOffset]::TryParseExact($timestampText, $format, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
                    $timestampUtc = $parsed.ToUniversalTime()
                    break
                }
            }
        }

        $entries += [PSCustomObject]@{
            Source = "nginx access"
            Raw = $line
            SourceIp = $sourceIp
            Method = $method
            Target = $target
            TimestampUtc = $timestampUtc
        }
    }

    return @($entries)
}

function Filter-EntriesByWindow {
    param(
        [object[]]$Entries,
        [DateTimeOffset]$WindowStartUtc,
        [DateTimeOffset]$WindowEndUtc,
        [string]$Source
    )

    $timestamped = @($Entries | Where-Object { $null -ne $_.TimestampUtc })
    $inWindow = @($timestamped | Where-Object { $_.TimestampUtc -ge $WindowStartUtc -and $_.TimestampUtc -le $WindowEndUtc })

    if ($timestamped.Count -eq 0 -and $Entries.Count -gt 0) {
        Add-CheckResult -Status "WARN" -Check "$Source timestamp filtering" -Details "No parseable timestamps found; checks may miss evidence"
    }

    return $inWindow
}

function Select-JsonMatches {
    param(
        [object[]]$Entries,
        [scriptblock]$Predicate
    )

    return @($Entries | Where-Object {
        $_.ParseOk -and $null -ne $_.Event -and (& $Predicate $_.Event $_.Raw)
    })
}

function Select-NginxMatches {
    param(
        [object[]]$Entries,
        [scriptblock]$Predicate
    )

    return @($Entries | Where-Object { & $Predicate $_ })
}

function Test-EventType {
    param(
        [object]$Event,
        [string]$EventType
    )

    return ((Get-EventValue -Event $Event -Name "event_type") -eq $EventType)
}

function Test-FieldEquals {
    param(
        [object]$Event,
        [string]$Field,
        [string]$Value
    )

    return ([string](Get-EventValue -Event $Event -Name $Field) -eq $Value)
}

function Test-ReasonLike {
    param(
        [object]$Event,
        [string]$Raw,
        [string]$Pattern
    )

    foreach ($field in @("reason", "result", "status", "message")) {
        $value = Get-EventValue -Event $Event -Name $field
        if ($value -and ([string]$value) -match $Pattern) {
            return $true
        }
    }

    return ($Raw -match $Pattern)
}

function Get-UsernameSet {
    param([object[]]$Entries)

    $names = @($Entries | ForEach-Object {
        if ($_.ParseOk -and $_.Event) {
            $username = Get-EventValue -Event $_.Event -Name "username"
            if ($username) {
                [string]$username
            }
        }
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)

    return $names
}

function Get-SourceSummary {
    param([string[]]$Sources)

    $validSources = @($Sources | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($validSources.Count -eq 0) {
        return [PSCustomObject]@{
            Total = 0
            SourceCount = 0
            DominantSourceIp = $null
            DominantSourceCount = 0
            SameSourceRequestRatio = 0.0
        }
    }

    $groups = @($validSources | Group-Object | Sort-Object Count -Descending)
    $dominant = $groups[0]
    return [PSCustomObject]@{
        Total = $validSources.Count
        SourceCount = $groups.Count
        DominantSourceIp = [string]$dominant.Name
        DominantSourceCount = [int]$dominant.Count
        SameSourceRequestRatio = [Math]::Round(([double]$dominant.Count / [double]$validSources.Count), 3)
    }
}

function Add-EvidenceCheck {
    param(
        [string]$Name,
        [object[]]$Matches,
        [string]$PassDetails,
        [string]$FailDetails,
        [ValidateSet("FAIL", "WARN")]
        [string]$MissingStatus = "FAIL"
    )

    if ($Matches.Count -gt 0) {
        Add-CheckResult -Status "PASS" -Check $Name -Details $PassDetails -MatchedLines @($Matches.Raw)
    }
    else {
        Add-CheckResult -Status $MissingStatus -Check $Name -Details $FailDetails
    }
}

function Add-CountCheck {
    param(
        [string]$Name,
        [object[]]$Matches,
        [int]$Minimum,
        [string]$PassDetails,
        [string]$FailDetails,
        [ValidateSet("FAIL", "WARN")]
        [string]$MissingStatus = "FAIL"
    )

    if ($Matches.Count -ge $Minimum) {
        Add-CheckResult -Status "PASS" -Check $Name -Details ("$PassDetails count=$($Matches.Count)") -MatchedLines @($Matches.Raw)
    }
    else {
        if ($Matches.Count -gt 0) {
            Add-CheckResult -Status $MissingStatus -Check $Name -Details ("$FailDetails count=$($Matches.Count), required=$Minimum") -MatchedLines @($Matches.Raw)
        }
        else {
            Add-CheckResult -Status $MissingStatus -Check $Name -Details ("$FailDetails count=$($Matches.Count), required=$Minimum")
        }
    }
}

function Test-DiversityMetadataFields {
    param([object]$Metadata)

    $requiredTextFields = @(
        "scenario_variant",
        "benign_activity_level",
        "generator_version",
        "target_endpoint_family"
    )

    foreach ($field in $requiredTextFields) {
        $value = [string](Get-EventValue -Event $Metadata -Name $field)
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            Add-CheckResult -Status "PASS" -Check "Metadata $field" -Details "$field=$value"
        }
        else {
            Add-CheckResult -Status "FAIL" -Check "Metadata $field" -Details "Missing or blank $field"
        }
    }

    foreach ($field in @("planned_request_count", "actual_request_count")) {
        $rawValue = Get-EventValue -Event $Metadata -Name $field
        $parsed = 0
        if ($null -ne $rawValue -and [int]::TryParse([string]$rawValue, [ref]$parsed) -and $parsed -gt 0) {
            Add-CheckResult -Status "PASS" -Check "Metadata $field" -Details "$field=$parsed"
        }
        else {
            Add-CheckResult -Status "FAIL" -Check "Metadata $field" -Details "Missing or non-positive $field"
        }
    }

    $safetyProperty = $Metadata.PSObject.Properties["safety_limit_applied"]
    if ($safetyProperty -and $safetyProperty.Value -is [bool]) {
        Add-CheckResult -Status "PASS" -Check "Metadata safety_limit_applied" -Details "safety_limit_applied=$($safetyProperty.Value)"
    }
    else {
        Add-CheckResult -Status "FAIL" -Check "Metadata safety_limit_applied" -Details "Missing boolean safety_limit_applied"
    }

    $scenario = [string](Get-EventValue -Event $Metadata -Name "scenario")
    $planned = 0
    [void][int]::TryParse([string](Get-EventValue -Event $Metadata -Name "planned_request_count"), [ref]$planned)
    if ($scenario -eq "LightDos" -and ($planned -lt 10 -or $planned -gt 50)) {
        Add-CheckResult -Status "FAIL" -Check "LightDos bounded planned_request_count" -Details "Expected 10..50; actual=$planned"
    }
    elseif ($scenario -eq "LightDos") {
        Add-CheckResult -Status "PASS" -Check "LightDos bounded planned_request_count" -Details "planned_request_count=$planned"
    }

    if ($scenario -eq "AttackerHostLightDos" -and ($planned -lt 20 -or $planned -gt 50)) {
        Add-CheckResult -Status "FAIL" -Check "AttackerHostLightDos bounded planned_request_count" -Details "Expected 20..50; actual=$planned"
    }
    elseif ($scenario -eq "AttackerHostLightDos") {
        Add-CheckResult -Status "PASS" -Check "AttackerHostLightDos bounded planned_request_count" -Details "planned_request_count=$planned"
    }

    if ($scenario -eq "MultiSourceLightDos" -and ($planned -lt 10 -or $planned -gt 60)) {
        Add-CheckResult -Status "FAIL" -Check "MultiSourceLightDos bounded planned_request_count" -Details "Expected 10..60; actual=$planned"
    }
    elseif ($scenario -eq "MultiSourceLightDos") {
        Add-CheckResult -Status "PASS" -Check "MultiSourceLightDos bounded planned_request_count" -Details "planned_request_count=$planned"
    }
}

function Test-BenignEvidence {
    param(
        [object]$Metadata,
        [object[]]$AuthEntries,
        [object[]]$WebEntries,
        [object[]]$NginxEntries
    )

    $variant = [string](Get-EventValue -Event $Metadata -Name "scenario_variant")
    $mainLabel = [string](Get-EventValue -Event $Metadata -Name "main_label")
    $scenario = [string](Get-EventValue -Event $Metadata -Name "scenario")
    $expectedFeatures = @($Metadata.expected_ml_features | ForEach-Object { [string]$_ })
    $actionCountNames = @()
    if ($Metadata.PSObject.Properties["action_counts"] -and $Metadata.action_counts) {
        $actionCountNames = @($Metadata.action_counts.PSObject.Properties.Name)
    }

    if ($scenario -eq "Benign") {
        Add-CheckResult -Status "PASS" -Check "Benign metadata scenario" -Details "scenario=Benign"
    }
    else {
        Add-CheckResult -Status "FAIL" -Check "Benign metadata scenario" -Details "Expected scenario=Benign; actual=$scenario"
    }

    if ($mainLabel -eq "Benign") {
        Add-CheckResult -Status "PASS" -Check "Benign metadata main_label" -Details "main_label=Benign"
    }
    else {
        Add-CheckResult -Status "FAIL" -Check "Benign metadata main_label" -Details "Expected main_label=Benign; actual=$mainLabel"
    }

    if (-not [string]::IsNullOrWhiteSpace($variant)) {
        Add-CheckResult -Status "PASS" -Check "Benign metadata scenario_variant" -Details "scenario_variant=$variant"
    }
    else {
        Add-CheckResult -Status "FAIL" -Check "Benign metadata scenario_variant" -Details "Missing scenario_variant for benign run"
    }

    $distributedProperty = $Metadata.PSObject.Properties["distributed"]
    if ($scenario -ne "MultiSourceLightDos" -and (-not $distributedProperty -or $distributedProperty.Value -ne $true)) {
        Add-CheckResult -Status "PASS" -Check "Benign not distributed metadata" -Details "No distributed=true metadata present"
    }
    else {
        Add-CheckResult -Status "FAIL" -Check "Benign not distributed metadata" -Details "Benign run must not carry MultiSourceLightDos/distributed metadata"
    }

    $webEvidence = @(Select-JsonMatches $WebEntries { param($e, $raw)
        (Test-EventType $e "page_view") -or
        (Test-EventType $e "search_query") -or
        (Test-EventType $e "request_completed") -or
        (Test-EventType $e "web_login_attempt") -or
        (Test-EventType $e "admin_route_access")
    })
    Add-CountCheck "Benign webapp evidence in window" $webEvidence 1 "Found webapp benign evidence" "Missing webapp evidence in benign run window"

    $nginxEvidence = @(Select-NginxMatches $NginxEntries { param($n)
        $n.Method -in @("GET", "POST") -and (
            $n.Target -eq "/" -or
            $n.Target -eq "/health" -or
            $n.Target -eq "/login" -or
            $n.Target -like "/search*"
        )
    })
    Add-CountCheck "Benign nginx evidence in window" $nginxEvidence 1 "Found nginx benign evidence" "Missing nginx evidence in benign run window"

    $pageViews = @(Select-JsonMatches $WebEntries { param($e, $raw) Test-EventType $e "page_view" })
    $homepageViews = @(Select-JsonMatches $WebEntries { param($e, $raw) (Test-EventType $e "page_view") -and (Test-FieldEquals $e "path" "/") })
    $loginPageViews = @(Select-JsonMatches $WebEntries { param($e, $raw) (Test-EventType $e "page_view") -and (Test-FieldEquals $e "path" "/login") })
    $searchQueries = @(Select-JsonMatches $WebEntries { param($e, $raw) Test-EventType $e "search_query" })
    $normalSearchQueries = @($searchQueries | Where-Object {
        $query = [string](Get-EventValue -Event $_.Event -Name "query")
        $query -notmatch "(?i)UNION\s+SELECT|information_schema|DROP\s+TABLE|OR\s+1\s*=\s*1|admin'--|attacker|attack|ddos|dos|flood|exploit|burst"
    })
    $healthWeb = @(Select-JsonMatches $WebEntries { param($e, $raw)
        ([string](Get-EventValue -Event $e -Name "path") -eq "/health") -or
        ([string](Get-EventValue -Event $e -Name "endpoint") -eq "/health") -or
        ([string](Get-EventValue -Event $e -Name "query") -match "(?i)service status")
    })
    $healthNginx = @(Select-NginxMatches $NginxEntries { param($n)
        $n.Target -eq "/health" -or $n.Target -match "(?i)service%20status|service\+status|service status"
    })
    $requestCompleted = @(Select-JsonMatches $WebEntries { param($e, $raw) Test-EventType $e "request_completed" })
    $successfulWebLogins = @(Select-JsonMatches $WebEntries { param($e, $raw) (Test-EventType $e "web_login_attempt") -and (Test-ReasonLike $e $raw "login_success") })
    $successfulAuthLogins = @(Select-JsonMatches $AuthEntries { param($e, $raw) Test-EventType $e "login_success" })
    $adminAccess = @(Select-JsonMatches $WebEntries { param($e, $raw) Test-EventType $e "admin_route_access" })
    $failedLogins = @(
        @(Select-JsonMatches $AuthEntries { param($e, $raw) Test-EventType $e "login_failed" }) +
        @(Select-JsonMatches $WebEntries { param($e, $raw) (Test-EventType $e "web_login_attempt") -and (Test-ReasonLike $e $raw "login_failed") })
    )

    $suspicious = @(Select-JsonMatches $WebEntries { param($e, $raw)
        (Test-EventType $e "suspicious_query") -or
        ([string](Get-EventValue -Event $e -Name "suspicious") -eq "true") -or
        ($raw -match "(?i)UNION\s+SELECT|information_schema|DROP\s+TABLE|OR\s+1\s*=\s*1|admin'--")
    })
    if ($suspicious.Count -eq 0) {
        Add-CheckResult -Status "PASS" -Check "Benign no SQLi/suspicious indicators" -Details "No SQLi/suspicious query evidence found"
    }
    else {
        Add-CheckResult -Status "FAIL" -Check "Benign no SQLi/suspicious indicators" -Details "Found suspicious/SQLi-like evidence in benign window" -MatchedLines @($suspicious.Raw)
    }

    $attackMarkers = @($WebEntries | Where-Object {
        $_.Raw -match "(?i)attacker-host-burst|attacker|ddos|dos_http|single_source_dos|distributed_dos|http_flood|exploit|UNION\s+SELECT|information_schema|DROP\s+TABLE|OR\s+1\s*=\s*1"
    })
    if ($attackMarkers.Count -eq 0) {
        Add-CheckResult -Status "PASS" -Check "Benign no attack markers" -Details "No attack-specific strings found in benign webapp evidence"
    }
    else {
        Add-CheckResult -Status "FAIL" -Check "Benign no attack markers" -Details "Found attack-specific strings in benign evidence" -MatchedLines @($attackMarkers.Raw)
    }

    if ($failedLogins.Count -lt 5) {
        Add-CheckResult -Status "PASS" -Check "Benign no large failed-login burst" -Details "failed_login_count=$($failedLogins.Count)"
    }
    else {
        Add-CheckResult -Status "FAIL" -Check "Benign no large failed-login burst" -Details "failed_login_count=$($failedLogins.Count), threshold=5" -MatchedLines @($failedLogins.Raw)
    }

    if ($failedLogins.Count -lt 5 -or (($successfulWebLogins.Count + $successfulAuthLogins.Count) -eq 0)) {
        Add-CheckResult -Status "PASS" -Check "Benign no success after large failure burst" -Details "failed_login_count=$($failedLogins.Count), success_count=$(($successfulWebLogins.Count + $successfulAuthLogins.Count))"
    }
    else {
        Add-CheckResult -Status "FAIL" -Check "Benign no success after large failure burst" -Details "Large failed-login burst followed by login success in benign window"
    }

    switch ($variant) {
        "normal_browsing" {
            Add-CountCheck "Benign normal_browsing page or search evidence" (@($pageViews) + @($normalSearchQueries)) 1 "Found normal page/search activity" "Missing normal browsing page/search activity"
        }
        "heavy_search_benign" {
            Add-CountCheck "Benign heavy_search normal queries" $normalSearchQueries 3 "Found multiple normal search queries" "Missing multiple normal search queries"
        }
        "healthcheck_heavy_benign" {
            Add-CountCheck "Benign healthcheck_heavy health/service-status evidence" (@($healthWeb) + @($healthNginx)) 2 "Found repeated health/service-status evidence" "Missing repeated health/service-status evidence"
            Add-CountCheck "Benign healthcheck_heavy page/search context" (@($homepageViews) + @($loginPageViews) + @($normalSearchQueries)) 1 "Found benign page/search context" "Missing benign page/search context"
        }
        "repeated_endpoint_benign" {
            $repeatedGroups = @($requestCompleted | ForEach-Object { [string](Get-EventValue -Event $_.Event -Name "path") } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Group-Object | Where-Object { $_.Count -ge 2 })
            if ($repeatedGroups.Count -gt 0) {
                Add-CheckResult -Status "PASS" -Check "Benign repeated_endpoint normal repeated path" -Details (($repeatedGroups | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join "; ")
            }
            else {
                Add-CheckResult -Status "FAIL" -Check "Benign repeated_endpoint normal repeated path" -Details "No repeated normal endpoint access found"
            }
        }
        "mixed_user_journey_benign" {
            Add-CountCheck "Benign mixed_user_journey page/search evidence" (@($homepageViews) + @($loginPageViews) + @($normalSearchQueries)) 2 "Found mixed user journey page/search evidence" "Missing mixed user journey page/search evidence"
        }
        "benign_burst_without_attack" {
            Add-CountCheck "Benign bounded burst normal requests" (@($requestCompleted) + @($nginxEvidence)) 5 "Found bounded normal request burst" "Missing bounded normal request burst"
            $hardNegativeProperty = $Metadata.PSObject.Properties["expected_hard_negative"]
            if (-not $hardNegativeProperty -or $hardNegativeProperty.Value -eq $true) {
                Add-CheckResult -Status "PASS" -Check "Benign burst hard-negative metadata" -Details "expected_hard_negative=$($hardNegativeProperty.Value)"
            }
            else {
                Add-CheckResult -Status "FAIL" -Check "Benign burst hard-negative metadata" -Details "expected_hard_negative must be true when present"
            }
        }
        default {
            Add-CountCheck "Benign generic page/search evidence" (@($pageViews) + @($normalSearchQueries)) 1 "Found generic benign page/search activity" "Missing generic benign page/search activity"
        }
    }

    $requiresSuccessfulLogin = (
        ($variant -in @("normal_browsing", "mixed_user_journey_benign")) -and
        (
            ($actionCountNames | Where-Object { $_ -like "POST /login*" }).Count -gt 0 -or
            ($expectedFeatures -contains "successful_login_count" -and $variant -eq "mixed_user_journey_benign")
        )
    )
    if ($requiresSuccessfulLogin) {
        Add-CountCheck "Benign conditional web login success" $successfulWebLogins 1 "Found expected web login_success" "Missing expected web login_success"
        Add-CountCheck "Benign conditional auth login success" $successfulAuthLogins 1 "Found expected auth login_success" "Missing expected auth login_success"
    }
    else {
        Add-CheckResult -Status "PASS" -Check "Benign login/admin optional for variant" -Details "variant=$variant does not require successful login/admin evidence"
    }

    if ($adminAccess.Count -gt 0) {
        Add-CheckResult -Status "PASS" -Check "Benign optional admin access evidence" -Details "admin_route_access_count=$($adminAccess.Count)" -MatchedLines @($adminAccess.Raw)
    }

    $hardNegative = [string](Get-EventValue -Event $Metadata -Name "expected_hard_negative")
    if ($hardNegative -eq "True" -or $hardNegative -eq "true" -or $variant -match "heavy|repeated|burst|mixed") {
        $repeatedBenign = @($WebEntries | Where-Object {
            (Test-EventType $_.Event "request_completed") -and
            (
                ([string](Get-EventValue -Event $_.Event -Name "path") -eq "/health") -or
                ([string](Get-EventValue -Event $_.Event -Name "path") -eq "/") -or
                ([string](Get-EventValue -Event $_.Event -Name "path") -eq "/login") -or
                ([string](Get-EventValue -Event $_.Event -Name "path") -like "/search*")
            )
        })
        Add-CountCheck "Benign hard-negative repeated legitimate requests" $repeatedBenign 5 "Found repeated legitimate benign request_completed events" "Missing repeated legitimate hard-negative benign evidence" -MissingStatus "WARN"
    }
}

function Test-UnauthorizedAccessEvidence {
    param(
        [object]$Metadata,
        [object[]]$AuthEntries,
        [object[]]$WebEntries
    )

    $sublabel = [string]$Metadata.sublabel

    Add-EvidenceCheck "UnauthorizedAccess web page_view /login" `
        (Select-JsonMatches $WebEntries { param($e, $raw) (Test-EventType $e "page_view") -and (Test-FieldEquals $e "path" "/login") }) `
        "Found login page_view" "Missing login page_view"

    Add-CountCheck "UnauthorizedAccess web login_failed" `
        (Select-JsonMatches $WebEntries { param($e, $raw) (Test-EventType $e "web_login_attempt") -and (Test-ReasonLike $e $raw "login_failed") }) `
        1 "Found web_login_attempt login_failed" "Missing web_login_attempt login_failed"

    Add-CountCheck "UnauthorizedAccess auth login_failed" `
        (Select-JsonMatches $AuthEntries { param($e, $raw) Test-EventType $e "login_failed" }) `
        1 "Found auth login_failed" "Missing auth login_failed"

    $unknownMatches = @(Select-JsonMatches $AuthEntries { param($e, $raw) Test-ReasonLike $e $raw "unknown_user" })
    $uniqueUsers = @(Get-UsernameSet (@($AuthEntries) + @($WebEntries)))
    if ($unknownMatches.Count -gt 0 -or $uniqueUsers.Count -gt 1) {
        $lines = @($unknownMatches.Raw)
        Add-CheckResult -Status "PASS" -Check "UnauthorizedAccess unknown user or username diversity" -Details "unknown_user_count=$($unknownMatches.Count), unique_username_count=$($uniqueUsers.Count)" -MatchedLines $lines
    }
    else {
        Add-CheckResult -Status "FAIL" -Check "UnauthorizedAccess unknown user or username diversity" -Details "Missing unknown_user evidence and multiple usernames"
    }

    if ($sublabel -match "ato_progression|success_after_failures") {
        Add-EvidenceCheck "UnauthorizedAccess conditional auth login_success admin" `
            (Select-JsonMatches $AuthEntries { param($e, $raw) (Test-EventType $e "login_success") -and (Test-FieldEquals $e "username" "admin") }) `
            "Found conditional auth login_success for admin" "Missing conditional auth login_success for admin"

        Add-EvidenceCheck "UnauthorizedAccess conditional web login_success" `
            (Select-JsonMatches $WebEntries { param($e, $raw) (Test-EventType $e "web_login_attempt") -and (Test-ReasonLike $e $raw "login_success") }) `
            "Found conditional web_login_attempt login_success" "Missing conditional web_login_attempt login_success"
    }
    else {
        Add-CheckResult -Status "WARN" -Check "UnauthorizedAccess success checks skipped" -Details "Sublabel '$sublabel' does not require login_success"
    }

    if ($sublabel -match "ato_progression") {
        Add-EvidenceCheck "UnauthorizedAccess conditional admin_route_access admin" `
            (Select-JsonMatches $WebEntries { param($e, $raw) (Test-EventType $e "admin_route_access") -and (Test-FieldEquals $e "username" "admin") }) `
            "Found conditional admin_route_access for admin" "Missing conditional admin_route_access for admin"
    }
}

function Test-SqliProbeEvidence {
    param(
        [object[]]$WebEntries,
        [object[]]$NginxEntries
    )

    Add-CountCheck "SqliProbe normal search_query" `
        (Select-JsonMatches $WebEntries { param($e, $raw) Test-EventType $e "search_query" }) `
        1 "Found normal search_query" "Missing normal search_query"

    $suspiciousMatches = @(Select-JsonMatches $WebEntries { param($e, $raw) Test-EventType $e "suspicious_query" })
    Add-CountCheck "SqliProbe suspicious_query" $suspiciousMatches 1 "Found suspicious_query" "Missing suspicious_query"

    Add-EvidenceCheck "SqliProbe nginx GET /search" `
        (Select-NginxMatches $NginxEntries { param($n) $n.Method -eq "GET" -and $n.Target -like "/search*" }) `
        "Found nginx GET /search" "Missing nginx GET /search"

    $patternMatches = @($suspiciousMatches | Where-Object {
        $query = [string](Get-EventValue -Event $_.Event -Name "query")
        ($query -match "(?i)OR\s+1\s*=\s*1|UNION\s+SELECT|information_schema|admin'--|DROP\s+TABLE") -or
        ($_.Raw -match "(?i)OR\s+1\s*=\s*1|UNION\s+SELECT|information_schema|admin'--|DROP\s+TABLE")
    })

    Add-CountCheck "SqliProbe SQLi-style content" $patternMatches 1 "Found SQLi-style content in suspicious_query" "Missing recognizable SQLi-style content"
}

function Get-LightDosThreshold {
    param([string]$Intensity)

    switch ($Intensity) {
        "Low" { return 8 }
        "Medium" { return 20 }
        "High" { return 40 }
        default { return 8 }
    }
}

function Test-LightDosEvidence {
    param(
        [object]$Metadata,
        [object[]]$WebEntries,
        [object[]]$NginxEntries
    )

    Add-EvidenceCheck "LightDos nginx GET /health" `
        (Select-NginxMatches $NginxEntries { param($n) $n.Method -eq "GET" -and $n.Target -eq "/health" }) `
        "Found nginx GET /health" "Missing nginx GET /health"

    Add-EvidenceCheck "LightDos nginx GET /" `
        (Select-NginxMatches $NginxEntries { param($n) $n.Method -eq "GET" -and $n.Target -eq "/" }) `
        "Found nginx GET /" "Missing nginx GET /"

    $nginxBurst = @(Select-NginxMatches $NginxEntries { param($n) $n.Method -eq "GET" -and $n.Target -like "/search?q=burst-*" })
    Add-CountCheck "LightDos nginx burst search requests" $nginxBurst 2 "Found repeated nginx burst searches" "Missing repeated nginx burst searches"

    $webBurst = @(Select-JsonMatches $WebEntries { param($e, $raw)
        (Test-EventType $e "search_query") -and (
            ([string](Get-EventValue -Event $e -Name "query") -like "burst-*") -or
            ($raw -match "burst-")
        )
    })
    Add-CountCheck "LightDos webapp burst search_query" $webBurst 2 "Found repeated webapp burst searches" "Missing repeated webapp burst searches"

    $plannedRequestCount = [int](Get-EventValue -Event $Metadata -Name "planned_request_count")
    $threshold = if ($plannedRequestCount -gt 0) {
        [Math]::Max(1, [int][Math]::Floor($plannedRequestCount * 0.8))
    }
    else {
        Get-LightDosThreshold -Intensity ([string]$Metadata.intensity)
    }
    $relatedRequests = @($NginxEntries | Where-Object {
        $_.Method -eq "GET" -and ($_.Target -eq "/" -or $_.Target -eq "/health" -or $_.Target -eq "/login" -or $_.Target -like "/search?q=burst-*")
    })
    Add-CountCheck "LightDos request count threshold" $relatedRequests $threshold "Found enough related light-DoS requests" "Not enough related light-DoS requests"

    Add-EvidenceCheck "LightDos webapp status_code field" `
        (Select-JsonMatches $WebEntries { param($e, $raw) $null -ne (Get-EventValue -Event $e -Name "status_code") }) `
        "Found webapp status_code service-impact evidence" `
        "Missing webapp status_code field; old logs remain compatible, but new runs should include it" `
        -MissingStatus "WARN"

    Add-EvidenceCheck "LightDos webapp duration field" `
        (Select-JsonMatches $WebEntries { param($e, $raw)
            ($null -ne (Get-EventValue -Event $e -Name "response_time_ms")) -or
            ($null -ne (Get-EventValue -Event $e -Name "request_duration_ms"))
        }) `
        "Found webapp response_time_ms or request_duration_ms service-impact evidence" `
        "Missing webapp response_time_ms/request_duration_ms; old logs remain compatible, but new runs should include one" `
        -MissingStatus "WARN"

    Add-EvidenceCheck "LightDos webapp source_ip field" `
        (Select-JsonMatches $WebEntries { param($e, $raw) -not [string]::IsNullOrWhiteSpace([string](Get-EventValue -Event $e -Name "source_ip")) }) `
        "Found webapp source_ip service-impact evidence" `
        "Missing webapp source_ip field; old logs remain compatible, but new runs should include it" `
        -MissingStatus "WARN"

    Add-EvidenceCheck "LightDos webapp path field" `
        (Select-JsonMatches $WebEntries { param($e, $raw) -not [string]::IsNullOrWhiteSpace([string](Get-EventValue -Event $e -Name "path")) }) `
        "Found webapp path field" `
        "Missing webapp path field; old logs remain compatible, but new runs should include it" `
        -MissingStatus "WARN"

    Add-EvidenceCheck "LightDos webapp method field" `
        (Select-JsonMatches $WebEntries { param($e, $raw) -not [string]::IsNullOrWhiteSpace([string](Get-EventValue -Event $e -Name "method")) }) `
        "Found webapp method field" `
        "Missing webapp method field; old logs remain compatible, but new runs should include it" `
        -MissingStatus "WARN"

    Add-CheckResult -Status "WARN" -Check "LightDos outage expectation" -Details "Absence of service outage is expected and is not a failure"
}

function Test-AttackerHostLightDosEvidence {
    param(
        [object]$Metadata,
        [object[]]$WebEntries,
        [object[]]$NginxEntries
    )

    $metadataAttackerIp = [string](Get-EventValue -Event $Metadata -Name "attacker_source_ip")
    if (-not [string]::IsNullOrWhiteSpace($metadataAttackerIp)) {
        Add-CheckResult -Status "PASS" -Check "AttackerHostLightDos metadata attacker_source_ip" -Details "attacker_source_ip=$metadataAttackerIp"
    }
    else {
        Add-CheckResult -Status "FAIL" -Check "AttackerHostLightDos metadata attacker_source_ip" -Details "Missing attacker_source_ip"
    }

    $distributedProperty = $Metadata.PSObject.Properties["distributed"]
    if ($distributedProperty -and $distributedProperty.Value -eq $false) {
        Add-CheckResult -Status "PASS" -Check "AttackerHostLightDos metadata distributed" -Details "distributed=false"
    }
    else {
        Add-CheckResult -Status "FAIL" -Check "AttackerHostLightDos metadata distributed" -Details "Expected distributed=false; actual=$($distributedProperty.Value)"
    }

    $metadataSourceCount = [int](Get-EventValue -Event $Metadata -Name "source_count")
    if ($metadataSourceCount -eq 1) {
        Add-CheckResult -Status "PASS" -Check "AttackerHostLightDos metadata source_count" -Details "source_count=1"
    }
    else {
        Add-CheckResult -Status "FAIL" -Check "AttackerHostLightDos metadata source_count" -Details "Expected source_count=1; actual=$metadataSourceCount"
    }

    $attackMode = [string](Get-EventValue -Event $Metadata -Name "attack_mode")
    if ($attackMode -eq "DoS_HTTP_Flood") {
        Add-CheckResult -Status "PASS" -Check "AttackerHostLightDos metadata attack_mode" -Details "attack_mode=DoS_HTTP_Flood"
    }
    else {
        Add-CheckResult -Status "FAIL" -Check "AttackerHostLightDos metadata attack_mode" -Details "Expected DoS_HTTP_Flood; actual=$attackMode"
    }

    $webBurst = @(Select-JsonMatches $WebEntries { param($e, $raw)
        ([string](Get-EventValue -Event $e -Name "query") -like "attacker-host-burst-*") -or
        ($raw -match "attacker-host-burst-")
    })
    $webBurstSearches = @($webBurst | Where-Object { Test-EventType $_.Event "search_query" })
    Add-CountCheck "AttackerHostLightDos burst_search_count" $webBurstSearches 1 "Found Windows-host burst search_query events" "Missing attacker-host burst search_query events"

    $webBurstCompleted = @(Select-JsonMatches $WebEntries { param($e, $raw)
        (Test-EventType $e "request_completed") -and (
            ([string](Get-EventValue -Event $e -Name "query") -like "attacker-host-burst-*") -or
            ($raw -match "attacker-host-burst-")
        )
    })
    Add-CountCheck "AttackerHostLightDos request_completed events" $webBurstCompleted 1 "Found burst request_completed events" "Missing burst request_completed events"

    $webBurstWithSource = @($webBurst | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string](Get-EventValue -Event $_.Event -Name "source_ip"))
    })
    if ($webBurst.Count -gt 0 -and $webBurstWithSource.Count -eq $webBurst.Count) {
        Add-CheckResult -Status "PASS" -Check "AttackerHostLightDos webapp burst source_ip fields" -Details "All $($webBurst.Count) burst event(s) contain source_ip" -MatchedLines @($webBurst.Raw)
    }
    else {
        Add-CheckResult -Status "FAIL" -Check "AttackerHostLightDos webapp burst source_ip fields" -Details "Burst events=$($webBurst.Count), with source_ip=$($webBurstWithSource.Count)"
    }

    $nginxBurst = @(Select-NginxMatches $NginxEntries { param($n)
        $n.Method -eq "GET" -and $n.Target -like "/search?q=attacker-host-burst-*"
    })
    $plannedRequestCount = [int](Get-EventValue -Event $Metadata -Name "planned_request_count")
    $nginxThreshold = if ($plannedRequestCount -gt 0) {
        [Math]::Max(1, [int][Math]::Floor($plannedRequestCount * 0.8))
    }
    else {
        Get-LightDosThreshold -Intensity ([string]$Metadata.intensity)
    }
    Add-CountCheck "AttackerHostLightDos nginx access burst threshold" $nginxBurst $nginxThreshold "Found enough nginx attacker-host burst requests" "Not enough nginx attacker-host burst requests"

    $nginxBurstWithSource = @($nginxBurst | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.SourceIp) })
    if ($nginxBurst.Count -gt 0 -and $nginxBurstWithSource.Count -eq $nginxBurst.Count) {
        Add-CheckResult -Status "PASS" -Check "AttackerHostLightDos nginx burst SourceIp fields" -Details "All $($nginxBurst.Count) nginx burst entry/entries contain SourceIp" -MatchedLines @($nginxBurst.Raw)
    }
    else {
        Add-CheckResult -Status "FAIL" -Check "AttackerHostLightDos nginx burst SourceIp fields" -Details "Nginx burst entries=$($nginxBurst.Count), with SourceIp=$($nginxBurstWithSource.Count)"
    }

    $webSourceSummary = Get-SourceSummary -Sources @($webBurstWithSource | ForEach-Object { [string](Get-EventValue -Event $_.Event -Name "source_ip") })
    $nginxSourceSummary = Get-SourceSummary -Sources @($nginxBurstWithSource | ForEach-Object { [string]$_.SourceIp })

    if ($webSourceSummary.SourceCount -eq 1) {
        Add-CheckResult -Status "PASS" -Check "AttackerHostLightDos webapp observed source count" -Details "observed_source_count=1 dominant_source_ip=$($webSourceSummary.DominantSourceIp)"
    }
    else {
        Add-CheckResult -Status "FAIL" -Check "AttackerHostLightDos webapp observed source count" -Details "Expected 1 source; observed=$($webSourceSummary.SourceCount)"
    }

    if ($nginxSourceSummary.SourceCount -eq 1) {
        Add-CheckResult -Status "PASS" -Check "AttackerHostLightDos nginx observed source count" -Details "observed_source_count=1 dominant_source_ip=$($nginxSourceSummary.DominantSourceIp)"
    }
    else {
        Add-CheckResult -Status "FAIL" -Check "AttackerHostLightDos nginx observed source count" -Details "Expected 1 source; observed=$($nginxSourceSummary.SourceCount)"
    }

    if ($webSourceSummary.SameSourceRequestRatio -ge 0.95) {
        Add-CheckResult -Status "PASS" -Check "AttackerHostLightDos webapp same_source_request_ratio" -Details "ratio=$($webSourceSummary.SameSourceRequestRatio)"
    }
    else {
        Add-CheckResult -Status "FAIL" -Check "AttackerHostLightDos webapp same_source_request_ratio" -Details "Expected ratio >= 0.95; actual=$($webSourceSummary.SameSourceRequestRatio)"
    }

    if ($nginxSourceSummary.SameSourceRequestRatio -ge 0.95) {
        Add-CheckResult -Status "PASS" -Check "AttackerHostLightDos nginx same_source_request_ratio" -Details "ratio=$($nginxSourceSummary.SameSourceRequestRatio)"
    }
    else {
        Add-CheckResult -Status "FAIL" -Check "AttackerHostLightDos nginx same_source_request_ratio" -Details "Expected ratio >= 0.95; actual=$($nginxSourceSummary.SameSourceRequestRatio)"
    }

    $completedWithStatus = @($webBurstCompleted | Where-Object { $null -ne (Get-EventValue -Event $_.Event -Name "status_code") })
    if ($webBurstCompleted.Count -gt 0 -and $completedWithStatus.Count -eq $webBurstCompleted.Count) {
        Add-CheckResult -Status "PASS" -Check "AttackerHostLightDos status_code fields" -Details "All burst request_completed events contain status_code"
    }
    else {
        Add-CheckResult -Status "FAIL" -Check "AttackerHostLightDos status_code fields" -Details "Burst request_completed=$($webBurstCompleted.Count), with status_code=$($completedWithStatus.Count)"
    }

    $completedWithDuration = @($webBurstCompleted | Where-Object {
        ($null -ne (Get-EventValue -Event $_.Event -Name "response_time_ms")) -or
        ($null -ne (Get-EventValue -Event $_.Event -Name "request_duration_ms"))
    })
    if ($webBurstCompleted.Count -gt 0 -and $completedWithDuration.Count -eq $webBurstCompleted.Count) {
        Add-CheckResult -Status "PASS" -Check "AttackerHostLightDos duration fields" -Details "All burst request_completed events contain response_time_ms or request_duration_ms"
    }
    else {
        Add-CheckResult -Status "FAIL" -Check "AttackerHostLightDos duration fields" -Details "Burst request_completed=$($webBurstCompleted.Count), with duration=$($completedWithDuration.Count)"
    }

    if (-not [string]::IsNullOrWhiteSpace($metadataAttackerIp) -and
        $metadataAttackerIp -eq $webSourceSummary.DominantSourceIp -and
        $metadataAttackerIp -eq $nginxSourceSummary.DominantSourceIp) {
        Add-CheckResult -Status "PASS" -Check "AttackerHostLightDos source IP agreement" -Details "metadata=$metadataAttackerIp webapp=$($webSourceSummary.DominantSourceIp) nginx=$($nginxSourceSummary.DominantSourceIp)"
    }
    else {
        Add-CheckResult -Status "WARN" -Check "AttackerHostLightDos source IP agreement" -Details "metadata attacker_source_ip=$metadataAttackerIp; observed webapp dominant source IP=$($webSourceSummary.DominantSourceIp); observed nginx dominant source IP=$($nginxSourceSummary.DominantSourceIp)"
    }

    $classification = if ($webSourceSummary.SourceCount -gt 1 -or $nginxSourceSummary.SourceCount -gt 1) {
        "Multiple visible sources observed; only a future multi-source scenario may be described as DDoS-like evidence."
    }
    else {
        "One visible source observed; classify as single-source DoS evidence, not DDoS."
    }
    Add-CheckResult -Status "PASS" -Check "AttackerHostLightDos DoS/DDoS-ready classification" -Details $classification
}

function Test-MixedDemoEvidence {
    param(
        [object[]]$WebEntries,
        [object[]]$NginxEntries
    )

    Add-CheckResult -Status "WARN" -Check "MixedDemo training label warning" -Details "MixedDemo is useful for dashboards and correlation, not clean supervised training"

    Add-CountCheck "MixedDemo normal search_query" `
        (Select-JsonMatches $WebEntries { param($e, $raw) Test-EventType $e "search_query" }) `
        1 "Found normal search_query" "Missing normal search_query"

    Add-CountCheck "MixedDemo suspicious_query" `
        (Select-JsonMatches $WebEntries { param($e, $raw) Test-EventType $e "suspicious_query" }) `
        1 "Found suspicious_query" "Missing suspicious_query"

    Add-CountCheck "MixedDemo web login_failed" `
        (Select-JsonMatches $WebEntries { param($e, $raw) (Test-EventType $e "web_login_attempt") -and (Test-ReasonLike $e $raw "login_failed") }) `
        1 "Found web_login_attempt login_failed" "Missing web_login_attempt login_failed"

    Add-CountCheck "MixedDemo web login_success" `
        (Select-JsonMatches $WebEntries { param($e, $raw) (Test-EventType $e "web_login_attempt") -and (Test-ReasonLike $e $raw "login_success") }) `
        1 "Found web_login_attempt login_success" "Missing web_login_attempt login_success"

    Add-CountCheck "MixedDemo admin_route_access" `
        (Select-JsonMatches $WebEntries { param($e, $raw) Test-EventType $e "admin_route_access" }) `
        1 "Found admin_route_access" "Missing admin_route_access"

    $webBurstMixed = @(Select-JsonMatches $WebEntries { param($e, $raw) $raw -match "burst-mixed" })
    $nginxBurstMixed = @(Select-NginxMatches $NginxEntries { param($n) $n.Raw -match "burst-mixed" })
    $combinedBurst = @($webBurstMixed) + @($nginxBurstMixed)
    Add-CountCheck "MixedDemo burst-mixed evidence" $combinedBurst 2 "Found burst-mixed evidence" "Missing burst-mixed evidence"
}

function Add-WindowCountCheck {
    param(
        [string]$Name,
        [int]$Count,
        [bool]$ReadSucceeded
    )

    if ($ReadSucceeded -and $Count -gt 0) {
        Add-CheckResult -Status "PASS" -Check $Name -Details "$Count timestamped line(s) in window"
    }
    elseif ($ReadSucceeded) {
        Add-CheckResult -Status "WARN" -Check $Name -Details "0 timestamped line(s) in window"
    }
    else {
        Add-CheckResult -Status "WARN" -Check $Name -Details "Log read failed; no timestamped lines available"
    }
}

function Print-MatchedLines {
    foreach ($result in $script:CheckResults) {
        $lines = @($result.MatchedLines)
        if ($lines.Count -eq 0) {
            continue
        }

        Write-Host "`n[$($result.Status)] $($result.Check) matched lines:" -ForegroundColor DarkCyan
        foreach ($line in $lines | Select-Object -First 20) {
            Write-Host "  $line"
        }
        if ($lines.Count -gt 20) {
            Write-Host "  ... $($lines.Count - 20) more line(s)"
        }
    }
}

function Get-ServicePressureWebMatches {
    param([object[]]$WebEntries)

    return @($WebEntries | Where-Object {
        (Test-EventType $_.Event "request_completed") -or
        (Test-EventType $_.Event "search_query") -or
        (Test-EventType $_.Event "page_view")
    })
}

function Get-ServicePressureNginxMatches {
    param([object[]]$NginxEntries)

    return @($NginxEntries | Where-Object {
        $_.Method -eq "GET" -and (
            $_.Target -eq "/" -or
            $_.Target -eq "/health" -or
            $_.Target -eq "/login" -or
            $_.Target -like "/search*"
        )
    })
}

function Test-ServiceImpactFields {
    param(
        [string]$Prefix,
        [object[]]$WebMatches
    )

    $completed = @($WebMatches | Where-Object { Test-EventType $_.Event "request_completed" })
    Add-CountCheck "$Prefix request_completed events" $completed 1 "Found request_completed events" "Missing request_completed service-impact events" -MissingStatus "WARN"

    Add-EvidenceCheck "$Prefix webapp status_code field" `
        (@($completed | Where-Object { $null -ne (Get-EventValue -Event $_.Event -Name "status_code") })) `
        "Found status_code service-impact evidence" `
        "Missing status_code field; old logs remain compatible, but new runs should include it" `
        -MissingStatus "WARN"

    Add-EvidenceCheck "$Prefix webapp duration field" `
        (@($completed | Where-Object {
            ($null -ne (Get-EventValue -Event $_.Event -Name "response_time_ms")) -or
            ($null -ne (Get-EventValue -Event $_.Event -Name "request_duration_ms"))
        })) `
        "Found response_time_ms or request_duration_ms evidence" `
        "Missing response_time_ms/request_duration_ms; old logs remain compatible, but new runs should include one" `
        -MissingStatus "WARN"
}

function Test-LightDosEvidence {
    param(
        [object]$Metadata,
        [object[]]$WebEntries,
        [object[]]$NginxEntries
    )

    $plannedRequestCount = [int](Get-EventValue -Event $Metadata -Name "planned_request_count")
    $threshold = if ($plannedRequestCount -gt 0) {
        [Math]::Max(1, [int][Math]::Floor($plannedRequestCount * 0.7))
    }
    else {
        Get-LightDosThreshold -Intensity ([string]$Metadata.intensity)
    }

    $relatedRequests = Get-ServicePressureNginxMatches -NginxEntries $NginxEntries
    $webPressure = Get-ServicePressureWebMatches -WebEntries $WebEntries
    Add-CountCheck "LightDos request count threshold" $relatedRequests $threshold "Found enough related light-DoS requests" "Not enough related light-DoS requests"

    $pathGroups = @($relatedRequests | Group-Object Target | Where-Object { $_.Count -ge 2 })
    if ($pathGroups.Count -gt 0) {
        Add-CheckResult -Status "PASS" -Check "LightDos repeated target path family" -Details (($pathGroups | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join "; ")
    }
    else {
        Add-CheckResult -Status "FAIL" -Check "LightDos repeated target path family" -Details "No repeated normal target path family found"
    }

    Test-ServiceImpactFields -Prefix "LightDos" -WebMatches $webPressure
    Add-CheckResult -Status "WARN" -Check "LightDos outage expectation" -Details "Absence of service outage is expected and is not a failure"
}

function Test-AttackerHostLightDosEvidence {
    param(
        [object]$Metadata,
        [object[]]$WebEntries,
        [object[]]$NginxEntries
    )

    $metadataAttackerIp = [string](Get-EventValue -Event $Metadata -Name "attacker_source_ip")
    if (-not [string]::IsNullOrWhiteSpace($metadataAttackerIp)) {
        Add-CheckResult -Status "PASS" -Check "AttackerHostLightDos metadata attacker_source_ip" -Details "attacker_source_ip=$metadataAttackerIp"
    }
    else {
        Add-CheckResult -Status "FAIL" -Check "AttackerHostLightDos metadata attacker_source_ip" -Details "Missing attacker_source_ip"
    }

    $distributedProperty = $Metadata.PSObject.Properties["distributed"]
    if ($distributedProperty -and $distributedProperty.Value -eq $false) {
        Add-CheckResult -Status "PASS" -Check "AttackerHostLightDos metadata distributed" -Details "distributed=false"
    }
    else {
        Add-CheckResult -Status "FAIL" -Check "AttackerHostLightDos metadata distributed" -Details "Expected distributed=false; actual=$($distributedProperty.Value)"
    }

    $relatedRequests = Get-ServicePressureNginxMatches -NginxEntries $NginxEntries
    $webPressure = Get-ServicePressureWebMatches -WebEntries $WebEntries
    $plannedRequestCount = [int](Get-EventValue -Event $Metadata -Name "planned_request_count")
    $threshold = if ($plannedRequestCount -gt 0) { [Math]::Max(1, [int][Math]::Floor($plannedRequestCount * 0.7)) } else { Get-LightDosThreshold -Intensity ([string]$Metadata.intensity) }
    Add-CountCheck "AttackerHostLightDos nginx service-pressure threshold" $relatedRequests $threshold "Found enough nginx service-pressure requests" "Not enough nginx service-pressure requests"

    $webSourceSummary = Get-SourceSummary -Sources @($webPressure | ForEach-Object { [string](Get-EventValue -Event $_.Event -Name "source_ip") })
    $nginxSourceSummary = Get-SourceSummary -Sources @($relatedRequests | ForEach-Object { [string]$_.SourceIp })

    if ($webSourceSummary.SourceCount -eq 1 -or $nginxSourceSummary.SourceCount -eq 1) {
        Add-CheckResult -Status "PASS" -Check "AttackerHostLightDos observed single source" -Details "webapp_sources=$($webSourceSummary.SourceCount) nginx_sources=$($nginxSourceSummary.SourceCount)"
    }
    else {
        Add-CheckResult -Status "FAIL" -Check "AttackerHostLightDos observed single source" -Details "Expected single-source DoS evidence; webapp_sources=$($webSourceSummary.SourceCount) nginx_sources=$($nginxSourceSummary.SourceCount)"
    }

    if ($webSourceSummary.SameSourceRequestRatio -ge 0.95 -or $nginxSourceSummary.SameSourceRequestRatio -ge 0.95) {
        Add-CheckResult -Status "PASS" -Check "AttackerHostLightDos source concentration" -Details "webapp_ratio=$($webSourceSummary.SameSourceRequestRatio) nginx_ratio=$($nginxSourceSummary.SameSourceRequestRatio)"
    }
    else {
        Add-CheckResult -Status "FAIL" -Check "AttackerHostLightDos source concentration" -Details "Expected ratio >= 0.95; webapp_ratio=$($webSourceSummary.SameSourceRequestRatio) nginx_ratio=$($nginxSourceSummary.SameSourceRequestRatio)"
    }

    Test-ServiceImpactFields -Prefix "AttackerHostLightDos" -WebMatches $webPressure
    Add-CheckResult -Status "PASS" -Check "AttackerHostLightDos DoS/DDoS-ready classification" -Details "One visible source expected; classify as single-source DoS evidence, not DDoS."
}

function Test-MultiSourceLightDosEvidence {
    param(
        [object]$Metadata,
        [object[]]$WebEntries,
        [object[]]$NginxEntries
    )

    $minVisibleSources = [int](Get-EventValue -Event $Metadata -Name "min_visible_sources")
    if ($minVisibleSources -lt 2) {
        $minVisibleSources = 2
    }

    $relatedRequests = Get-ServicePressureNginxMatches -NginxEntries $NginxEntries
    $webPressure = Get-ServicePressureWebMatches -WebEntries $WebEntries
    $webSourceSummary = Get-SourceSummary -Sources @($webPressure | ForEach-Object { [string](Get-EventValue -Event $_.Event -Name "source_ip") })
    $nginxSourceSummary = Get-SourceSummary -Sources @($relatedRequests | ForEach-Object { [string]$_.SourceIp })

    if ($webSourceSummary.SourceCount -ge $minVisibleSources -or $nginxSourceSummary.SourceCount -ge $minVisibleSources) {
        Add-CheckResult -Status "PASS" -Check "MultiSourceLightDos visible source count" -Details "webapp_sources=$($webSourceSummary.SourceCount) nginx_sources=$($nginxSourceSummary.SourceCount)"
    }
    else {
        Add-CheckResult -Status "FAIL" -Check "MultiSourceLightDos visible source count" -Details "MultiSourceLightDos cannot be treated as distributed; expected >=$minVisibleSources visible sources, webapp=$($webSourceSummary.SourceCount), nginx=$($nginxSourceSummary.SourceCount)"
    }

    if (($webSourceSummary.SourceCount -ge $minVisibleSources -and $webSourceSummary.SameSourceRequestRatio -lt 0.95) -or
        ($nginxSourceSummary.SourceCount -ge $minVisibleSources -and $nginxSourceSummary.SameSourceRequestRatio -lt 0.95)) {
        Add-CheckResult -Status "PASS" -Check "MultiSourceLightDos source distribution" -Details "webapp_ratio=$($webSourceSummary.SameSourceRequestRatio) nginx_ratio=$($nginxSourceSummary.SameSourceRequestRatio)"
    }
    else {
        Add-CheckResult -Status "FAIL" -Check "MultiSourceLightDos source distribution" -Details "Expected multi-source concentration below single-source threshold; webapp_ratio=$($webSourceSummary.SameSourceRequestRatio), nginx_ratio=$($nginxSourceSummary.SameSourceRequestRatio)"
    }

    $plannedRequestCount = [int](Get-EventValue -Event $Metadata -Name "planned_request_count")
    $threshold = if ($plannedRequestCount -gt 0) { [Math]::Max(1, [int][Math]::Floor($plannedRequestCount * 0.7)) } else { 10 }
    Add-CountCheck "MultiSourceLightDos request threshold" $relatedRequests $threshold "Found enough related multi-source requests" "Not enough related multi-source requests"
    Test-ServiceImpactFields -Prefix "MultiSourceLightDos" -WebMatches $webPressure
}

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

$startTimeUtc = Convert-ToUtcDateTimeOffset -Value ([string]$metadata.start_time_utc)
$endTimeUtc = Convert-ToUtcDateTimeOffset -Value ([string]$metadata.end_time_utc)

if (-not $startTimeUtc -or -not $endTimeUtc) {
    Write-Host "Metadata is missing parseable start_time_utc or end_time_utc." -ForegroundColor Red
    exit 1
}

$windowStartUtc = $startTimeUtc.AddSeconds(-1 * $TimePaddingSeconds)
$windowEndUtc = $endTimeUtc.AddSeconds($TimePaddingSeconds)

Write-Host "============================================================"
Write-Host "Coding Fest 2026 XDR Telemetry Verification"
Write-Host "============================================================"
Write-Host "Metadata:       $MetadataPath"
Write-Host "RunId:          $($metadata.run_id)"
Write-Host "Scenario:       $($metadata.scenario)"
Write-Host "Main label:     $($metadata.main_label)"
Write-Host "Sublabel:       $($metadata.sublabel)"
Write-Host "Actor profile:  $($metadata.actor_profile)"
Write-Host "Intensity:      $($metadata.intensity)"
Write-Host "Start UTC:      $($metadata.start_time_utc)"
Write-Host "End UTC:        $($metadata.end_time_utc)"
Write-Host "Window UTC:     $($windowStartUtc.ToString('o')) to $($windowEndUtc.ToString('o'))"
Write-Host "Log sources:    $(@($metadata.expected_log_sources) -join ', ')"
Write-Host "ML features:    $(@($metadata.expected_ml_features) -join ', ')"
Write-Host "Read mode:      $(if ($UseLocalLogs) { 'local cached logs' } else { 'remote multipass logs' })"
if ($UseLocalLogs) {
    Write-Host "Local auth:     $LocalAuthLogPath"
    Write-Host "Local webapp:   $LocalWebLogPath"
    Write-Host "Local nginx:    $LocalNginxLogPath"
}
Write-Host "============================================================"

$authNeeded = Test-ExpectedLogSource -Metadata $metadata -Path $AuthLogPath
$webNeeded = Test-ExpectedLogSource -Metadata $metadata -Path $WebLogPath
$nginxNeeded = Test-ExpectedLogSource -Metadata $metadata -Path $NginxAccessLogPath

if ($authNeeded) {
    if ($UseLocalLogs) {
        $authRead = Read-LocalLog -SourceName "auth log" -Path $LocalAuthLogPath
    }
    else {
        $authRead = Read-RemoteLog -HostName $AuthHost -Path $AuthLogPath
    }
}
else {
    $authRead = New-SkippedLogRead -HostName $AuthHost -Path $AuthLogPath -Reason "not listed in metadata.expected_log_sources"
}

if ($webNeeded) {
    if ($UseLocalLogs) {
        $webRead = Read-LocalLog -SourceName "webapp log" -Path $LocalWebLogPath
    }
    else {
        $webRead = Read-RemoteLog -HostName $WebHost -Path $WebLogPath
    }
}
else {
    $webRead = New-SkippedLogRead -HostName $WebHost -Path $WebLogPath -Reason "not listed in metadata.expected_log_sources"
}

if ($nginxNeeded) {
    if ($UseLocalLogs) {
        $nginxRead = Read-LocalLog -SourceName "nginx access log" -Path $LocalNginxLogPath
    }
    else {
        $nginxRead = Read-RemoteLog -HostName $WebHost -Path $NginxAccessLogPath -UseSudo
    }
}
else {
    $nginxRead = New-SkippedLogRead -HostName $WebHost -Path $NginxAccessLogPath -Reason "not listed in metadata.expected_log_sources"
}

Add-LogReadCheck -Name "Read auth log" -ReadResult $authRead
Add-LogReadCheck -Name "Read webapp log" -ReadResult $webRead
Add-LogReadCheck -Name "Read nginx access log" -ReadResult $nginxRead

if ($authNeeded) {
    $authEntries = Filter-EntriesByWindow -Entries (Convert-JsonLogLines -Lines $authRead.Lines -Source "auth log") -WindowStartUtc $windowStartUtc -WindowEndUtc $windowEndUtc -Source "auth log"
    Add-WindowCountCheck -Name "Filtered auth log window" -Count $authEntries.Count -ReadSucceeded $authRead.Success
}
else {
    $authEntries = @()
}

if ($webNeeded) {
    $webEntries = Filter-EntriesByWindow -Entries (Convert-JsonLogLines -Lines $webRead.Lines -Source "webapp log") -WindowStartUtc $windowStartUtc -WindowEndUtc $windowEndUtc -Source "webapp log"
    Add-WindowCountCheck -Name "Filtered webapp log window" -Count $webEntries.Count -ReadSucceeded $webRead.Success
}
else {
    $webEntries = @()
}

if ($nginxNeeded) {
    $nginxEntries = Filter-EntriesByWindow -Entries (Convert-NginxAccessLines -Lines $nginxRead.Lines) -WindowStartUtc $windowStartUtc -WindowEndUtc $windowEndUtc -Source "nginx access log"
    Add-WindowCountCheck -Name "Filtered nginx access window" -Count $nginxEntries.Count -ReadSucceeded $nginxRead.Success
}
else {
    $nginxEntries = @()
}

Test-DiversityMetadataFields -Metadata $metadata

switch ([string]$metadata.scenario) {
    "Benign" { Test-BenignEvidence -Metadata $metadata -AuthEntries $authEntries -WebEntries $webEntries -NginxEntries $nginxEntries }
    "UnauthorizedAccess" { Test-UnauthorizedAccessEvidence -Metadata $metadata -AuthEntries $authEntries -WebEntries $webEntries }
    "SqliProbe" { Test-SqliProbeEvidence -WebEntries $webEntries -NginxEntries $nginxEntries }
    "LightDos" { Test-LightDosEvidence -Metadata $metadata -WebEntries $webEntries -NginxEntries $nginxEntries }
    "AttackerHostLightDos" { Test-AttackerHostLightDosEvidence -Metadata $metadata -WebEntries $webEntries -NginxEntries $nginxEntries }
    "MultiSourceLightDos" { Test-MultiSourceLightDosEvidence -Metadata $metadata -WebEntries $webEntries -NginxEntries $nginxEntries }
    "MixedDemo" { Test-MixedDemoEvidence -WebEntries $webEntries -NginxEntries $nginxEntries }
    default { Add-CheckResult -Status "FAIL" -Check "Scenario support" -Details "Unsupported scenario: $($metadata.scenario)" }
}

Write-Host "`n============================================================"
Write-Host "CHECKS"
Write-Host "============================================================"
$script:CheckResults |
    Select-Object Status, Check, Details |
    Format-Table -AutoSize -Wrap

if ($ShowMatchedLines) {
    Print-MatchedLines
}

$passed = @($script:CheckResults | Where-Object { $_.Status -eq "PASS" }).Count
$warnings = @($script:CheckResults | Where-Object { $_.Status -eq "WARN" }).Count
$failed = @($script:CheckResults | Where-Object { $_.Status -eq "FAIL" }).Count
$total = $script:CheckResults.Count
$verdict = if ($failed -eq 0) { "PASS" } elseif ($Strict) { "FAIL" } else { "FAIL_NON_STRICT" }

Write-Host "`n============================================================"
Write-Host "SUMMARY"
Write-Host "============================================================"
Write-Host "Total checks: $total"
Write-Host "Passed:       $passed"
Write-Host "Warnings:     $warnings"
Write-Host "Failed:       $failed"
Write-Host "Verdict:      $verdict"

if ($failed -gt 0) {
    Write-Host ""
    Write-Host "Failed checks:" -ForegroundColor Red
    foreach ($result in @($script:CheckResults | Where-Object { $_.Status -eq "FAIL" })) {
        Write-Host ("- {0}: {1}" -f $result.Check, $result.Details) -ForegroundColor Red
    }
}

if ($Strict -and $failed -gt 0) {
    exit 1
}

exit 0
