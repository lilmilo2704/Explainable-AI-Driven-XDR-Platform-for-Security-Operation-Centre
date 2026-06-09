<#
.SYNOPSIS
Builds rule-based weak explanation labels for window stages and evidence rows.

.DESCRIPTION
Reads an existing batch manifest, windowed dataset, and verified-run raw evidence
folders. Writes new explanation-label outputs only under the configured output
directory. Existing dataset, windowed, model-ready, quality, batch, and
verified-run files are read-only inputs.
#>

[CmdletBinding()]
param(
    [string]$BatchManifestPath = "exports\batches\training-batch-20260607T132426Z\batch-manifest.json",

    [string]$WindowedDatasetPath = "exports\windowed-datasets\training-batch-20260607T132426Z-windows.csv",

    [string]$OutputDir = "exports\explanation-labels",

    [ValidateRange(1, 500)]
    [int]$MaxEventsPerWindow = 30,

    [switch]$OnlyCleanTrainingCandidates,

    [switch]$Force
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
        if ($prop -and $null -ne $prop.Value -and -not [string]::IsNullOrWhiteSpace([string]$prop.Value)) {
            return $prop.Value
        }
    }
    return $Default
}

function Convert-ToUtc {
    param([object]$Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    try { return ([DateTimeOffset]::Parse([string]$Value)).UtcDateTime } catch { return $null }
}

function Convert-ToDouble {
    param([object]$Value, [double]$Default = 0.0)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $Default }
    $parsed = 0.0
    if ([double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
        return $parsed
    }
    return $Default
}

function Convert-ToInt {
    param([object]$Value, [int]$Default = 0)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $Default }
    $parsed = 0
    if ([int]::TryParse([string]$Value, [ref]$parsed)) { return $parsed }
    return $Default
}

function Convert-ToBool {
    param([object]$Value, [bool]$Default = $false)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $Default }
    if ([string]$Value -match '^(?i:true|1|yes)$') { return $true }
    if ([string]$Value -match '^(?i:false|0|no)$') { return $false }
    return $Default
}

function Format-Cell {
    param([object]$Value)
    if ($null -eq $Value) { return "" }
    if ($Value -is [double] -or $Value -is [float]) {
        return ([double]$Value).ToString("0.###", [System.Globalization.CultureInfo]::InvariantCulture)
    }
    return [string]$Value
}

function Get-SafeText {
    param([string]$Text, [int]$MaxLength = 1200)
    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    $clean = $Text -replace "[`r`n]+", " "
    if ($clean.Length -le $MaxLength) { return $clean }
    return $clean.Substring(0, $MaxLength) + "...[truncated]"
}

function Get-RunDirectory {
    param([string]$VerifiedRunsRoot, [string]$RunId)
    return Join-Path $VerifiedRunsRoot ($RunId -replace '[^A-Za-z0-9._-]', '_')
}

function Test-CleanCandidate {
    param([object]$Run, [string]$RunDir)
    if ([string](Get-Value -Object $Run -Names @("status")) -ne "completed") { return $false }
    if ([string](Get-Value -Object $Run -Names @("verification_status")) -ne "passed") { return $false }
    if ([string](Get-Value -Object $Run -Names @("export_status")) -ne "exported") { return $false }
    if (-not (Test-Path -LiteralPath $RunDir -PathType Container)) { return $false }

    $manifestPath = Join-Path $RunDir "manifest.json"
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        try {
            $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
            return (Convert-ToBool (Get-Value -Object $manifest -Names @("clean_supervised_training_candidate", "suitable_for_clean_supervised_training") -Default $true) -Default $true)
        }
        catch {
            return $false
        }
    }
    return $false
}

function Test-HighWindow {
    param([object]$Window)
    $rate = Convert-ToDouble $Window.request_rate_per_second
    $requests = Convert-ToInt $Window.request_count
    $completed = Convert-ToInt $Window.request_completed_count
    $existingStage = [string](Get-Value -Object $Window -Names @("stage_label"))
    return ($rate -ge 1.5 -or $requests -ge 8 -or $completed -ge 8 -or $existingStage -match "burst|sustained|service_stress")
}

function Test-ExplicitDegradation {
    param([object]$Window)
    $status5xx = Convert-ToInt $Window.status_5xx_count
    $healthFailed = Convert-ToInt $Window.health_check_failed_count
    $nginxErrors = Convert-ToInt $Window.nginx_error_count
    $maxLatency = Convert-ToDouble $Window.max_response_time_ms
    $p95Latency = Convert-ToDouble $Window.p95_response_time_ms
    return ($status5xx -gt 0 -or $healthFailed -gt 0 -or $nginxErrors -gt 0 -or $maxLatency -ge 1000 -or $p95Latency -ge 1000)
}

function Test-ServiceStress {
    param([object]$Window)
    if (-not (Test-HighWindow -Window $Window)) { return $false }
    $avgLatency = Convert-ToDouble $Window.avg_response_time_ms
    $maxLatency = Convert-ToDouble $Window.max_response_time_ms
    return ($avgLatency -ge 100 -or $maxLatency -ge 250)
}

function Get-StageDecision {
    param(
        [object]$Window,
        [int]$FirstHighWindowIndex,
        [int]$LastHighWindowIndex,
        [bool]$HasRawEvidence
    )

    $scenario = [string](Get-Value -Object $Window -Names @("scenario"))
    $mainLabel = [string](Get-Value -Object $Window -Names @("main_label"))
    $windowIndex = Convert-ToInt $Window.window_index
    $requestCount = Convert-ToInt $Window.request_count

    if (-not $HasRawEvidence) {
        return [PSCustomObject]@{
            Label = "unclear"
            Confidence = "low"
            Reason = "Raw evidence folder is missing for this window, so stage cannot be verified."
            NeedsReview = $true
        }
    }

    if ($mainLabel -eq "Benign" -or $scenario -eq "Benign") {
        if (Test-ExplicitDegradation -Window $Window) {
            return [PSCustomObject]@{
                Label = "unclear"
                Confidence = "low"
                Reason = "Benign-labelled window contains degradation-like fields and needs manual review."
                NeedsReview = $true
            }
        }
        return [PSCustomObject]@{
            Label = "baseline"
            Confidence = "high"
            Reason = "Benign-labelled window; normal activity is treated as baseline unless explicit impact evidence appears."
            NeedsReview = $false
        }
    }

    if ($mainLabel -eq "DoS_DDoS") {
        if (Test-ExplicitDegradation -Window $Window) {
            return [PSCustomObject]@{
                Label = "service_degradation"
                Confidence = "medium"
                Reason = "Explicit degradation evidence is present: 5xx, failed health check, nginx error, or severe latency spike."
                NeedsReview = $true
            }
        }
        if (Test-ServiceStress -Window $Window) {
            return [PSCustomObject]@{
                Label = "service_stress"
                Confidence = "medium"
                Reason = "High request volume is paired with latency or error-status evidence, but not enough for service_degradation."
                NeedsReview = $true
            }
        }
        if (Test-HighWindow -Window $Window) {
            if ($windowIndex -eq $FirstHighWindowIndex) {
                return [PSCustomObject]@{
                    Label = "burst_onset"
                    Confidence = "high"
                    Reason = "First high request-rate/service-pressure window for this DoS_DDoS run."
                    NeedsReview = $false
                }
            }
            return [PSCustomObject]@{
                Label = "sustained_pressure"
                Confidence = "high"
                Reason = "Later high request-rate/service-pressure window after the initial onset."
                NeedsReview = $false
            }
        }
        if ($LastHighWindowIndex -ge 0 -and $windowIndex -gt $LastHighWindowIndex -and $requestCount -le 1) {
            return [PSCustomObject]@{
                Label = "recovery"
                Confidence = "medium"
                Reason = "Request pressure drops after earlier high-pressure windows."
                NeedsReview = $false
            }
        }
    }

    return [PSCustomObject]@{
        Label = "unclear"
        Confidence = "low"
        Reason = "No deterministic rule confidently matched this window."
        NeedsReview = $true
    }
}

function Read-WebappEvidence {
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
                EventTimeUtc = $ts
                EventSource = "webapp"
                Host = "web-server"
                RawFile = "webapp-slice.log:$lineNo"
                EventType = [string](Get-Value -Object $event -Names @("event_type"))
                Method = [string](Get-Value -Object $event -Names @("method"))
                Path = [string](Get-Value -Object $event -Names @("path", "endpoint"))
                Query = [string](Get-Value -Object $event -Names @("query"))
                SourceIp = [string](Get-Value -Object $event -Names @("source_ip"))
                StatusCode = [string](Get-Value -Object $event -Names @("status_code"))
                ResponseTimeMs = [string](Get-Value -Object $event -Names @("response_time_ms", "request_duration_ms"))
                Decoder = ""
                RuleId = ""
                RuleLevel = ""
                Location = "webapp-slice.log"
                Text = $line
            }) | Out-Null
        }
        catch {
        }
    }
    return @($rows.ToArray())
}

function Read-NginxEvidence {
    param([string]$Path, [datetime]$StartUtc, [datetime]$EndUtc)
    $rows = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $lineNo = 0
    foreach ($line in (Get-Content -LiteralPath $Path)) {
        $lineNo++
        $match = [regex]::Match([string]$line, '^(?<source_ip>\S+)\s+.*?\[(?<timestamp>[^\]]+)\]\s+"(?<method>[A-Z]+)\s+(?<target>\S+)[^"]*"\s+(?<status>\d{3})')
        if (-not $match.Success) { continue }
        try {
            $ts = [DateTimeOffset]::ParseExact($match.Groups["timestamp"].Value, "dd/MMM/yyyy:HH:mm:ss zzz", [System.Globalization.CultureInfo]::InvariantCulture).UtcDateTime
            if ($ts -lt $StartUtc -or $ts -ge $EndUtc) { continue }
            $rows.Add([PSCustomObject]@{
                EventTimeUtc = $ts
                EventSource = "nginx_access"
                Host = "web-server"
                RawFile = "nginx-access-slice.log:$lineNo"
                EventType = "nginx_access"
                Method = $match.Groups["method"].Value
                Path = $match.Groups["target"].Value
                Query = ""
                SourceIp = $match.Groups["source_ip"].Value
                StatusCode = $match.Groups["status"].Value
                ResponseTimeMs = ""
                Decoder = ""
                RuleId = ""
                RuleLevel = ""
                Location = "nginx-access-slice.log"
                Text = $line
            }) | Out-Null
        }
        catch {
        }
    }
    return @($rows.ToArray())
}

function Read-WazuhEvidence {
    param([string]$Path, [string]$EventSource, [datetime]$StartUtc, [datetime]$EndUtc)
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

            $location = [string](Get-Value -Object $event -Names @("location") -Default "")
            $decoder = [string](Get-Value -Object $event.decoder -Names @("name") -Default "")
            $data = $event.data
            $fullLog = [string](Get-Value -Object $event -Names @("full_log") -Default $line)

            $pathValue = [string](Get-Value -Object $data -Names @("path", "endpoint", "url") -Default "")
            $sourceIp = [string](Get-Value -Object $data -Names @("source_ip", "srcip") -Default "")
            $statusCode = [string](Get-Value -Object $data -Names @("status_code", "id") -Default "")
            $responseTime = [string](Get-Value -Object $data -Names @("response_time_ms", "request_duration_ms", "health_check_latency_ms") -Default "")
            $eventType = [string](Get-Value -Object $data -Names @("event_type") -Default "wazuh_event")

            if ([string]::IsNullOrWhiteSpace($pathValue)) {
                $nginxMatch = [regex]::Match($fullLog, '"(?<method>[A-Z]+)\s+(?<path>\S+)[^"]*"\s+(?<status>\d{3})')
                if ($nginxMatch.Success) {
                    $pathValue = $nginxMatch.Groups["path"].Value
                    if ([string]::IsNullOrWhiteSpace($statusCode)) { $statusCode = $nginxMatch.Groups["status"].Value }
                }
            }

            $rows.Add([PSCustomObject]@{
                EventTimeUtc = $ts
                EventSource = $EventSource
                Host = [string](Get-Value -Object $event.agent -Names @("name", "id") -Default "")
                RawFile = "$(Split-Path -Leaf $Path):$lineNo"
                EventType = $eventType
                Method = [string](Get-Value -Object $data -Names @("method", "protocol") -Default "")
                Path = $pathValue
                Query = [string](Get-Value -Object $data -Names @("query") -Default "")
                SourceIp = $sourceIp
                StatusCode = $statusCode
                ResponseTimeMs = $responseTime
                Decoder = $decoder
                RuleId = [string](Get-Value -Object $event.rule -Names @("id") -Default "")
                RuleLevel = [string](Get-Value -Object $event.rule -Names @("level") -Default "")
                Location = $location
                Text = $fullLog
            }) | Out-Null
        }
        catch {
        }
    }
    return @($rows.ToArray())
}

function Test-HttpPressureEvidence {
    param([object]$Event, [object]$Window)
    $mainLabel = [string](Get-Value -Object $Window -Names @("main_label"))
    if ($mainLabel -ne "DoS_DDoS") { return $false }
    if (-not (Test-HighWindow -Window $Window)) { return $false }
    if ($Event.EventSource -in @("webapp", "nginx_access")) { return $true }
    if ($Event.EventSource -eq "wazuh_archive" -and ([string]$Event.Location -match "nginx|webapp|web-lab")) { return $true }
    return $false
}

function Get-EvidenceDecision {
    param([object]$Event, [object]$Window, [string]$StageLabel)

    $scenario = [string](Get-Value -Object $Window -Names @("scenario"))
    $mainLabel = [string](Get-Value -Object $Window -Names @("main_label"))
    $sourceRatio = Convert-ToDouble $Window.top_source_ip_ratio
    $sourceCount = Convert-ToInt $Window.unique_source_ip_count
    $statusCode = Convert-ToInt $Event.StatusCode
    $responseTime = Convert-ToDouble $Event.ResponseTimeMs
    $path = [string]$Event.Path
    $eventText = [string]$Event.Text
    $location = [string]$Event.Location
    $decoder = [string]$Event.Decoder
    $eventType = [string]$Event.EventType
    $httpContext = (
        $Event.EventSource -in @("webapp", "nginx_access") -or
        $location -match "nginx|webapp|web-lab" -or
        $decoder -match "json|web-accesslog" -or
        $eventText -match '(?i)"(GET|POST|PUT|DELETE|HEAD)\s+/'
    )
    $explicitServiceError = (
        ($httpContext -and $statusCode -ge 500) -or
        $eventText -match '(?i)service unavailable|connection refused|upstream.*failed|nginx error' -or
        ($httpContext -and $eventText -match '(?i)\btimeout\b|\btimed out\b')
    )

    if ($explicitServiceError) {
        if ($path -eq "/health" -or $eventText -match '(?i)health') {
            return [PSCustomObject]@{ Role = "health_check_failure"; Score = 3; Confidence = "high"; Reason = "Explicit health-check failure or service error evidence."; NeedsReview = $true }
        }
        return [PSCustomObject]@{ Role = "error_evidence"; Score = 3; Confidence = "high"; Reason = "Explicit 5xx, timeout, service unavailable, connection refused, or nginx error evidence."; NeedsReview = $true }
    }

    if ($responseTime -ge 1000) {
        return [PSCustomObject]@{ Role = "latency_evidence"; Score = 3; Confidence = "high"; Reason = "Severe response-time spike is present."; NeedsReview = $true }
    }

    if ($responseTime -ge 250) {
        return [PSCustomObject]@{ Role = "latency_evidence"; Score = 2; Confidence = "medium"; Reason = "Elevated response-time evidence is present."; NeedsReview = $false }
    }

    if ($Event.EventSource -eq "wazuh_alert") {
        if ($httpContext -and ($eventText -match '(?i)http|nginx|webapp|health|request_completed|access.log')) {
            return [PSCustomObject]@{ Role = "wazuh_alert_context"; Score = 1; Confidence = "medium"; Reason = "Wazuh alert has possible HTTP/service context but should not be treated as ground truth."; NeedsReview = $true }
        }
        return [PSCustomObject]@{ Role = "irrelevant"; Score = 0; Confidence = "high"; Reason = "Wazuh alert is unrelated SSH/PAM/sudo/session/system context for this service-stress story."; NeedsReview = $false }
    }

    if ($Event.EventSource -eq "wazuh_archive") {
        if ($location -match "nginx|webapp|web-lab" -or $decoder -match "web-accesslog" -or ($decoder -eq "json" -and $eventText -match '(?i)"service":"web-server"|request_completed|page_view|search_query|web_login_attempt|admin_route_access')) {
            return [PSCustomObject]@{ Role = "wazuh_confirmation"; Score = 2; Confidence = "high"; Reason = "Wazuh archive mirrors nginx/webapp HTTP evidence."; NeedsReview = $false }
        }
        return [PSCustomObject]@{ Role = "irrelevant"; Score = 0; Confidence = "high"; Reason = "Wazuh archive event is not HTTP pressure, nginx, webapp, or service-health evidence."; NeedsReview = $false }
    }

    if ($mainLabel -eq "Benign") {
        if ($Event.EventSource -in @("webapp", "nginx_access")) {
            $score = if ($eventType -eq "request_completed") { 2 } else { 1 }
            return [PSCustomObject]@{ Role = "baseline_sample"; Score = $score; Confidence = "high"; Reason = "Normal benign HTTP event provides a baseline sample."; NeedsReview = $false }
        }
        return [PSCustomObject]@{ Role = "irrelevant"; Score = 0; Confidence = "medium"; Reason = "Event does not materially support the benign baseline explanation."; NeedsReview = $false }
    }

    if ($Event.EventSource -eq "webapp" -and $eventType -eq "request_completed" -and (Test-HttpPressureEvidence -Event $Event -Window $Window)) {
        return [PSCustomObject]@{ Role = "webapp_request_completion"; Score = 3; Confidence = "high"; Reason = "Webapp request_completed event occurs during a DoS_DDoS high-pressure window."; NeedsReview = $false }
    }

    if ($Event.EventSource -eq "nginx_access" -and (Test-HttpPressureEvidence -Event $Event -Window $Window)) {
        return [PSCustomObject]@{ Role = "representative_burst_request"; Score = 3; Confidence = "high"; Reason = "nginx access event represents burst/service-pressure traffic in a DoS_DDoS window."; NeedsReview = $false }
    }

    if ($scenario -eq "AttackerHostLightDos" -and $sourceCount -eq 1 -and $sourceRatio -ge 0.95 -and $Event.EventSource -eq "webapp") {
        return [PSCustomObject]@{ Role = "source_concentration_evidence"; Score = 3; Confidence = "high"; Reason = "Repeated attacker-host webapp events are concentrated from one observed source IP."; NeedsReview = $false }
    }

    if ($StageLabel -eq "sustained_pressure" -and $Event.EventSource -in @("webapp", "nginx_access")) {
        return [PSCustomObject]@{ Role = "sustained_pressure_evidence"; Score = 2; Confidence = "medium"; Reason = "HTTP event supports sustained request pressure."; NeedsReview = $false }
    }

    if ($StageLabel -eq "service_stress" -and $Event.EventSource -in @("webapp", "nginx_access")) {
        return [PSCustomObject]@{ Role = "service_stress_evidence"; Score = 2; Confidence = "medium"; Reason = "HTTP event contributes to a service-stress window."; NeedsReview = $true }
    }

    return [PSCustomObject]@{ Role = "irrelevant"; Score = 0; Confidence = "medium"; Reason = "No deterministic evidence-attribution rule matched this event."; NeedsReview = $false }
}

function Get-EventPriority {
    param([object]$Decision, [object]$Event)
    $score = [int]$Decision.Score
    $sourcePriority = switch ($Event.EventSource) {
        "webapp" { 0 }
        "nginx_access" { 1 }
        "wazuh_archive" { 2 }
        "wazuh_alert" { 3 }
        default { 4 }
    }
    return ((3 - $score) * 10) + $sourcePriority
}

$resolvedBatch = Resolve-PathInRepo $BatchManifestPath
$resolvedWindows = Resolve-PathInRepo $WindowedDatasetPath
$resolvedOutputDir = Resolve-PathInRepo $OutputDir
$verifiedRunsRoot = Resolve-PathInRepo "exports\verified-runs"

if (-not (Test-Path -LiteralPath $resolvedBatch -PathType Leaf)) { throw "Batch manifest not found: $resolvedBatch" }
if (-not (Test-Path -LiteralPath $resolvedWindows -PathType Leaf)) { throw "Windowed dataset not found: $resolvedWindows" }

$batch = Get-Content -Raw -LiteralPath $resolvedBatch | ConvertFrom-Json
$batchId = [string]$batch.batch_id
if ([string]::IsNullOrWhiteSpace($batchId)) { throw "Batch manifest does not contain batch_id: $resolvedBatch" }

New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null

$stagePath = Join-Path $resolvedOutputDir "$batchId-stage-labels.csv"
$evidencePath = Join-Path $resolvedOutputDir "$batchId-evidence-labels.csv"
$summaryPath = Join-Path $resolvedOutputDir "$batchId-label-summary.json"
$guidePath = Join-Path $resolvedOutputDir "$batchId-LABEL_GUIDE.md"
$outputPaths = @($stagePath, $evidencePath, $summaryPath, $guidePath)

if (-not $Force) {
    $existing = @($outputPaths | Where-Object { Test-Path -LiteralPath $_ })
    if ($existing.Count -gt 0) {
        throw "Output files already exist. Use -Force to replace files in $resolvedOutputDir only: $($existing -join ', ')"
    }
}

$runsById = @{}
$cleanRunIds = New-Object 'System.Collections.Generic.HashSet[string]'
$missingRawEvidenceRuns = New-Object System.Collections.Generic.List[string]
foreach ($run in @($batch.runs)) {
    $runId = [string](Get-Value -Object $run -Names @("run_id"))
    if ([string]::IsNullOrWhiteSpace($runId)) { continue }
    $runsById[$runId] = $run
    $runDir = Get-RunDirectory -VerifiedRunsRoot $verifiedRunsRoot -RunId $runId
    if (Test-CleanCandidate -Run $run -RunDir $runDir) { [void]$cleanRunIds.Add($runId) }
    elseif (-not (Test-Path -LiteralPath $runDir -PathType Container)) { $missingRawEvidenceRuns.Add($runId) | Out-Null }
}

$windows = @(Import-Csv -LiteralPath $resolvedWindows)
if ($OnlyCleanTrainingCandidates) {
    $windows = @($windows | Where-Object { $cleanRunIds.Contains([string]$_.run_id) })
}

$windowsByRun = $windows | Group-Object run_id
$firstHighByRun = @{}
$lastHighByRun = @{}
foreach ($group in $windowsByRun) {
    $orderedWindows = @($group.Group | Sort-Object { Convert-ToInt $_.window_index })
    $highIndexes = @($orderedWindows | Where-Object { [string]$_.main_label -eq "DoS_DDoS" -and (Test-HighWindow -Window $_) } | ForEach-Object { Convert-ToInt $_.window_index })
    if ($highIndexes.Count -gt 0) {
        $firstHighByRun[$group.Name] = ($highIndexes | Measure-Object -Minimum).Minimum
        $lastHighByRun[$group.Name] = ($highIndexes | Measure-Object -Maximum).Maximum
    }
    else {
        $firstHighByRun[$group.Name] = -1
        $lastHighByRun[$group.Name] = -1
    }
}

$stageRows = New-Object System.Collections.Generic.List[object]
$evidenceRows = New-Object System.Collections.Generic.List[object]
$warnings = New-Object System.Collections.Generic.List[string]
$eventSequence = 0

foreach ($runGroup in @($windows | Group-Object run_id | Sort-Object Name)) {
    $runId = [string]$runGroup.Name
    $runDir = Get-RunDirectory -VerifiedRunsRoot $verifiedRunsRoot -RunId $runId
    $hasRawEvidence = Test-Path -LiteralPath $runDir -PathType Container
    $firstHigh = if ($firstHighByRun.ContainsKey($runId)) { [int]$firstHighByRun[$runId] } else { -1 }
    $lastHigh = if ($lastHighByRun.ContainsKey($runId)) { [int]$lastHighByRun[$runId] } else { -1 }
    $runWindows = @($runGroup.Group | Sort-Object { Convert-ToInt $_.window_index })

    $runStartValues = @($runWindows | ForEach-Object { Convert-ToUtc $_.window_start_utc } | Where-Object { $null -ne $_ })
    $runEndValues = @($runWindows | ForEach-Object { Convert-ToUtc $_.window_end_utc } | Where-Object { $null -ne $_ })
    $runEvents = @()
    if ($hasRawEvidence -and $runStartValues.Count -gt 0 -and $runEndValues.Count -gt 0) {
        $runStart = ($runStartValues | Sort-Object | Select-Object -First 1)
        $runEnd = ($runEndValues | Sort-Object | Select-Object -Last 1)
        $runEvents += @(Read-WebappEvidence -Path (Join-Path $runDir "webapp-slice.log") -StartUtc $runStart -EndUtc $runEnd)
        $runEvents += @(Read-NginxEvidence -Path (Join-Path $runDir "nginx-access-slice.log") -StartUtc $runStart -EndUtc $runEnd)
        $runEvents += @(Read-WazuhEvidence -Path (Join-Path $runDir "wazuh-archives-slice.json") -EventSource "wazuh_archive" -StartUtc $runStart -EndUtc $runEnd)
        $runEvents += @(Read-WazuhEvidence -Path (Join-Path $runDir "wazuh-alerts-slice.json") -EventSource "wazuh_alert" -StartUtc $runStart -EndUtc $runEnd)
    }

    foreach ($window in $runWindows) {
        $stageDecision = Get-StageDecision -Window $window -FirstHighWindowIndex $firstHigh -LastHighWindowIndex $lastHigh -HasRawEvidence $hasRawEvidence

        $stageRows.Add([PSCustomObject][ordered]@{
            run_id = $runId
            window_id = [string]$window.window_id
            scenario = [string]$window.scenario
            main_label = [string]$window.main_label
            window_start_utc = [string]$window.window_start_utc
            window_end_utc = [string]$window.window_end_utc
            request_count = Format-Cell $window.request_count
            request_rate = Format-Cell $window.request_rate_per_second
            observed_source_count = Format-Cell $window.unique_source_ip_count
            same_source_request_ratio = Format-Cell $window.top_source_ip_ratio
            status_5xx_count = Format-Cell $window.status_5xx_count
            avg_response_time_ms = Format-Cell $window.avg_response_time_ms
            stage_label = $stageDecision.Label
            label_source = "rule_based"
            label_confidence = $stageDecision.Confidence
            label_reason = $stageDecision.Reason
            needs_human_review = [bool]$stageDecision.NeedsReview
        }) | Out-Null

        if (-not $hasRawEvidence) {
            $warnings.Add("Missing raw evidence folder for window $($window.window_id) / run $runId") | Out-Null
            continue
        }

        $startUtc = Convert-ToUtc $window.window_start_utc
        $endUtc = Convert-ToUtc $window.window_end_utc
        if (-not $startUtc -or -not $endUtc) {
            $warnings.Add("Invalid window timestamp for $($window.window_id)") | Out-Null
            continue
        }

        $events = @($runEvents | Where-Object { $_.EventTimeUtc -ge $startUtc -and $_.EventTimeUtc -lt $endUtc })
        $classified = New-Object System.Collections.Generic.List[object]
        foreach ($event in $events) {
            $decision = Get-EvidenceDecision -Event $event -Window $window -StageLabel $stageDecision.Label
            $classified.Add([PSCustomObject]@{ Event = $event; Decision = $decision; Priority = Get-EventPriority -Decision $decision -Event $event }) | Out-Null
        }

        $selected = @($classified | Sort-Object Priority, @{ Expression = { $_.Event.EventTimeUtc } } | Select-Object -First $MaxEventsPerWindow)
        foreach ($item in $selected) {
            $eventSequence++
            $event = $item.Event
            $decision = $item.Decision
            $evidenceRows.Add([PSCustomObject][ordered]@{
                run_id = $runId
                window_id = [string]$window.window_id
                event_id = "evidence-$('{0:D7}' -f $eventSequence)"
                event_time_utc = $event.EventTimeUtc.ToString("o")
                event_source = [string]$event.EventSource
                host = [string]$event.Host
                raw_file = [string]$event.RawFile
                event_type = [string]$event.EventType
                path = [string]$event.Path
                source_ip = [string]$event.SourceIp
                status_code = [string]$event.StatusCode
                response_time_ms = [string]$event.ResponseTimeMs
                event_text = Get-SafeText ([string]$event.Text)
                evidence_role = [string]$decision.Role
                evidence_score = [int]$decision.Score
                label_source = "rule_based"
                label_confidence = [string]$decision.Confidence
                label_reason = [string]$decision.Reason
                needs_human_review = [bool]$decision.NeedsReview
            }) | Out-Null
        }
    }
}

$stageArray = @($stageRows.ToArray())
$evidenceArray = @($evidenceRows.ToArray())
$stageArray | Export-Csv -LiteralPath $stagePath -NoTypeInformation -Encoding UTF8
$evidenceArray | Export-Csv -LiteralPath $evidencePath -NoTypeInformation -Encoding UTF8

$stageCounts = @{}
foreach ($group in @($stageArray | Group-Object stage_label | Sort-Object Name)) { $stageCounts[$group.Name] = $group.Count }
$confidenceCounts = @{}
foreach ($group in @($stageArray | Group-Object label_confidence | Sort-Object Name)) { $confidenceCounts[$group.Name] = $group.Count }
$roleCounts = @{}
foreach ($group in @($evidenceArray | Group-Object evidence_role | Sort-Object Name)) { $roleCounts[$group.Name] = $group.Count }
$scoreCounts = @{}
foreach ($group in @($evidenceArray | Group-Object evidence_score | Sort-Object Name)) { $scoreCounts[[string]$group.Name] = $group.Count }

$summary = [ordered]@{
    batch_id = $batchId
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    label_source = "rule_based"
    weak_label_policy = "AI-assisted/rule-assisted weak explanation labels; not perfect manually verified human ground truth."
    parameters = [ordered]@{
        batch_manifest_path = $resolvedBatch
        windowed_dataset_path = $resolvedWindows
        output_dir = $resolvedOutputDir
        max_events_per_window = $MaxEventsPerWindow
        only_clean_training_candidates = [bool]$OnlyCleanTrainingCandidates
    }
    outputs = [ordered]@{
        stage_labels_csv = $stagePath
        evidence_labels_csv = $evidencePath
        label_summary_json = $summaryPath
        label_guide_md = $guidePath
    }
    input_counts = [ordered]@{
        manifest_runs = @($batch.runs).Count
        clean_training_candidate_runs = $cleanRunIds.Count
        window_rows_read = @(Import-Csv -LiteralPath $resolvedWindows).Count
        window_rows_labelled = $stageArray.Count
    }
    output_counts = [ordered]@{
        stage_rows = $stageArray.Count
        evidence_rows = $evidenceArray.Count
        stage_rows_needing_human_review = @($stageArray | Where-Object { Convert-ToBool $_.needs_human_review }).Count
        evidence_rows_needing_human_review = @($evidenceArray | Where-Object { Convert-ToBool $_.needs_human_review }).Count
    }
    stage_label_counts = $stageCounts
    stage_confidence_counts = $confidenceCounts
    evidence_role_counts = $roleCounts
    evidence_score_counts = $scoreCounts
    missing_raw_evidence_runs = @($missingRawEvidenceRuns.ToArray() | Sort-Object -Unique)
    warnings = @($warnings.ToArray())
    limitations = @(
        "Labels are deterministic weak labels for explanation-layer bootstrapping, not human-reviewed ground truth.",
        "service_degradation is only assigned for explicit 5xx, failed health check, nginx error, timeout/service-unavailable/connection-refused text, or severe latency spike.",
        "Most Wazuh SSH/PAM/sudo/session/system events are marked irrelevant because they do not directly prove HTTP service pressure.",
        "Event text is truncated in the evidence-label CSV to keep the file reviewable; raw logs remain in verified-run folders.",
        "The current dataset is controlled lab-generated and mostly single-source DoS/service-stress, not a complete real-world DDoS benchmark."
    )
}

$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

$stageCountLines = if ($stageCounts.Count -gt 0) {
    ($stageCounts.GetEnumerator() | Sort-Object Name | ForEach-Object { "- `$($_.Key)`: $($_.Value)" }) -join "`r`n"
} else { "- none" }
$roleLines = if ($roleCounts.Count -gt 0) {
    ($roleCounts.GetEnumerator() | Sort-Object Name | ForEach-Object { "- `$($_.Key)`: $($_.Value)" }) -join "`r`n"
} else { "- none" }
$scoreLines = if ($scoreCounts.Count -gt 0) {
    ($scoreCounts.GetEnumerator() | Sort-Object Name | ForEach-Object { "- `$($_.Key)`: $($_.Value)" }) -join "`r`n"
} else { "- none" }

@"
# Explanation Label Guide - $batchId

These labels are AI-assisted / rule-assisted weak explanation labels. They are not perfect manually verified human ground truth.

## Outputs

- Stage labels: `$stagePath`
- Evidence labels: `$evidencePath`
- Summary: `$summaryPath`

## Stage Labels

- `baseline`
- `burst_onset`
- `sustained_pressure`
- `service_stress`
- `service_degradation`
- `recovery`
- `unclear`

## Evidence Roles

- `baseline_sample`
- `representative_burst_request`
- `source_concentration_evidence`
- `distributed_source_evidence`
- `sustained_pressure_evidence`
- `service_stress_evidence`
- `latency_evidence`
- `error_evidence`
- `health_check_failure`
- `nginx_access_evidence`
- `webapp_request_completion`
- `wazuh_confirmation`
- `wazuh_alert_context`
- `irrelevant`

## Evidence Scores

- `0` = irrelevant
- `1` = weak supporting evidence
- `2` = useful supporting evidence
- `3` = strong evidence that should appear in the incident graph/report

## Review Policy

Every row includes `label_source`, `label_confidence`, `label_reason`, and `needs_human_review`.

Rows marked `unclear`, low-confidence rows, and degradation-related rows should be reviewed before use as training ground truth.

Do not label `service_degradation` unless explicit evidence exists, such as 5xx status, failed health check, timeout, service unavailable, connection refused, nginx error, or severe latency spike.

Single-source `AttackerHostLightDos` is not true DDoS and should not be treated as distributed evidence unless multiple visible source IPs exist.

Wazuh SSH/PAM/sudo/session/system events are usually irrelevant to the HTTP service-stress explanation.

## Current Counts

Stage labels:

$stageCountLines

Evidence roles:

$roleLines

Evidence scores:

$scoreLines
"@ | Set-Content -LiteralPath $guidePath -Encoding UTF8

Write-Host "Explanation labels built for $batchId"
Write-Host "Stage rows: $($stageArray.Count)"
Write-Host "Evidence rows: $($evidenceArray.Count)"
Write-Host "Stage labels: $stagePath"
Write-Host "Evidence labels: $evidencePath"
Write-Host "Summary: $summaryPath"
Write-Host "Guide: $guidePath"
