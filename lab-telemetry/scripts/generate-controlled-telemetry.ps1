# generate-controlled-telemetry.ps1
# Generates labelled, bounded telemetry for the Coding Fest 2026 XDR lab.
# Run from Windows PowerShell after scripts/start-and-check-lab.ps1 is healthy.

[CmdletBinding()]
param(
    [string]$WebBase = "http://192.168.1.109",
    [string]$AuthBase = "http://192.168.1.102:8000",

    [ValidateSet("Benign", "UnauthorizedAccess", "SqliProbe", "LightDos", "AttackerHostLightDos", "MultiSourceLightDos", "MixedDemo")]
    [string]$Scenario = "Benign",

    [ValidateRange(1, 100)]
    [int]$Rounds = 1,

    [ValidateRange(0, 60000)]
    [int]$DelayMs = 300,

    [string]$RunId,

    [switch]$Randomize,

    [string]$OutputMetadataPath = "exports/latest-run-metadata.json",

    [ValidateSet("Low", "Medium", "High")]
    [string]$Intensity = "Low",

    [ValidateSet("normal_user", "careless_user", "attacker_single_ip", "attacker_noisy", "demo_operator")]
    [string]$ActorProfile = "demo_operator",

    [string[]]$SourceHosts = @("windows"),

    [switch]$RequireMultipleSources,

    [ValidateRange(2, 10)]
    [int]$MinVisibleSources = 2,

    [ValidateSet("explicit_lab_sources")]
    [string]$MultiSourceMode = "explicit_lab_sources",

    [ValidateRange(1, 50)]
    [int]$MaxRequestsPerSource = 20,

    [ValidateRange(1, 100)]
    [int]$TotalRequestCap = 60
)

$ErrorActionPreference = "Continue"

$ExpectedLogSourcesByScenario = @{
    Benign = @(
        "/home/ubuntu/auth-lab/logs/auth.log",
        "/home/ubuntu/web-lab/logs/webapp.log",
        "/var/log/nginx/access.log"
    )
    UnauthorizedAccess = @(
        "/home/ubuntu/auth-lab/logs/auth.log",
        "/home/ubuntu/web-lab/logs/webapp.log",
        "/var/log/nginx/access.log"
    )
    SqliProbe = @(
        "/home/ubuntu/web-lab/logs/webapp.log",
        "/var/log/nginx/access.log"
    )
    LightDos = @(
        "/home/ubuntu/web-lab/logs/webapp.log",
        "/var/log/nginx/access.log"
    )
    AttackerHostLightDos = @(
        "/home/ubuntu/web-lab/logs/webapp.log",
        "/var/log/nginx/access.log"
    )
    MultiSourceLightDos = @(
        "/home/ubuntu/web-lab/logs/webapp.log",
        "/var/log/nginx/access.log"
    )
    MixedDemo = @(
        "/home/ubuntu/auth-lab/logs/auth.log",
        "/home/ubuntu/web-lab/logs/webapp.log",
        "/var/log/nginx/access.log"
    )
}

$script:ActionCounts = [ordered]@{}
$script:BenignNoise = $false
$script:RoundSublabels = New-Object System.Collections.Generic.List[string]
$script:ScenarioVariants = New-Object System.Collections.Generic.List[string]
$script:BenignActivityLevels = New-Object System.Collections.Generic.List[string]
$script:RandomSeed = $null
$script:Rng = $null
$script:ConsecutiveRequestFailures = 0
$script:AttackerSourceIp = $null
$script:SourceIpDetectionMethod = $null
$script:PlannedRequestCount = $null
$script:ActualRequestCount = 0
$script:RequestCap = $null
$script:LightDosRequestCap = 50
$script:AttackerHostRequestCap = 50
$script:ExpectedHardNegative = $false
$script:MultiSourceObservedSourceCount = 0
$script:MultiSourceSourceHosts = @()
$script:MultiSourceSourceIps = @()
$script:DurationCapSeconds = $null
$script:TargetPaths = @()
$script:TargetEndpointFamily = $null
$script:SafetyLimitApplied = $false
$script:SafetyLimitReasons = New-Object System.Collections.Generic.List[string]
$script:GeneratorVersion = "controlled-telemetry-v0.2-diversity"

function Write-Step {
    param([string]$Message)
    Write-Host ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Message)
}

function Add-ActionCount {
    param([string]$Name)

    if (-not $script:ActionCounts.Contains($Name)) {
        $script:ActionCounts[$Name] = 0
    }

    $script:ActionCounts[$Name]++
}

function Add-ActualRequestCount {
    $script:ActualRequestCount++
}

function Add-PlannedRequestCount {
    param([int]$Count)

    if ($Count -le 0) {
        return
    }

    if ($null -eq $script:PlannedRequestCount) {
        $script:PlannedRequestCount = 0
    }

    $script:PlannedRequestCount += $Count
}

function Add-SafetyLimitReason {
    param([string]$Reason)

    $script:SafetyLimitApplied = $true
    if (-not [string]::IsNullOrWhiteSpace($Reason) -and -not $script:SafetyLimitReasons.Contains($Reason)) {
        $script:SafetyLimitReasons.Add($Reason) | Out-Null
    }
}

function Get-StableSeed {
    param([string]$Text)

    $inputText = if ([string]::IsNullOrWhiteSpace($Text)) { "controlled-telemetry" } else { $Text }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($inputText)
        $hash = $sha.ComputeHash($bytes)
        $seed = [BitConverter]::ToInt32($hash, 0)
        if ($seed -eq [int]::MinValue) {
            return 20260602
        }

        return [Math]::Abs($seed)
    }
    finally {
        $sha.Dispose()
    }
}

function Get-DistinctSummary {
    param(
        [object[]]$Values,
        [string]$Default = "not_applicable"
    )

    $distinct = @($Values | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
    if ($distinct.Count -eq 0) {
        return $Default
    }

    if ($distinct.Count -eq 1) {
        return [string]$distinct[0]
    }

    return "varied:$($distinct -join ',')"
}

function Select-CountInRange {
    param(
        [int]$Minimum,
        [int]$Maximum
    )

    if ($Maximum -lt $Minimum) {
        return $Minimum
    }

    return $script:Rng.Next($Minimum, $Maximum + 1)
}

function Get-BoundedRequestCount {
    param(
        [string]$ScenarioName,
        [int]$LowMinimum,
        [int]$LowMaximum,
        [int]$MediumMinimum,
        [int]$MediumMaximum,
        [int]$HardCap
    )

    $min = $LowMinimum
    $max = $LowMaximum

    switch ($Intensity) {
        "Low" {
            $min = $LowMinimum
            $max = $LowMaximum
        }
        "Medium" {
            $min = $MediumMinimum
            $max = $MediumMaximum
        }
        "High" {
            $min = $MediumMinimum
            $max = $MediumMaximum
            Add-SafetyLimitReason "$ScenarioName High intensity requested; bounded Medium range applied"
        }
    }

    if ($max -gt $HardCap) {
        $max = $HardCap
        Add-SafetyLimitReason "$ScenarioName request range capped at $HardCap"
    }

    if ($min -gt $HardCap) {
        $min = $HardCap
        Add-SafetyLimitReason "$ScenarioName minimum request range capped at $HardCap"
    }

    return Select-CountInRange -Minimum $min -Maximum $max
}

function Test-LabPrivateIPv4 {
    param([string]$TargetHostName)

    if ($TargetHostName -notmatch "^(?:\d{1,3}\.){3}\d{1,3}$") {
        return $false
    }

    if ($TargetHostName -match "^192\.168\." -or
        $TargetHostName -match "^10\." -or
        $TargetHostName -match "^172\.(1[6-9]|2[0-9]|3[0-1])\.") {
        return $true
    }

    return $false
}

function Get-WindowsSourceIpForTarget {
    $targetUri = [Uri]$WebBase
    $socket = $null

    try {
        $socket = [System.Net.Sockets.Socket]::new(
            [System.Net.Sockets.AddressFamily]::InterNetwork,
            [System.Net.Sockets.SocketType]::Dgram,
            [System.Net.Sockets.ProtocolType]::Udp
        )
        $targetPort = if ($targetUri.Port -gt 0) { $targetUri.Port } else { 80 }
        $socket.Connect($targetUri.Host, $targetPort)
        $address = [string]$socket.LocalEndPoint.Address

        if (Test-LabPrivateIPv4 -TargetHostName $address) {
            return [PSCustomObject]@{
                IpAddress = $address
                Method = "udp_route_socket_to_target"
            }
        }
    }
    catch {
        Write-Host "  WARN: Route-selected Windows source IP detection failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    finally {
        if ($socket) {
            $socket.Dispose()
        }
    }

    try {
        $fallback = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object {
                $_.IPAddress -notlike "127.*" -and
                $_.IPAddress -notlike "169.254.*" -and
                (Test-LabPrivateIPv4 -TargetHostName ([string]$_.IPAddress))
            } |
            Select-Object -First 1

        if ($fallback) {
            return [PSCustomObject]@{
                IpAddress = [string]$fallback.IPAddress
                Method = "Get-NetIPAddress_fallback_uncertain"
            }
        }
    }
    catch {
        Write-Host "  WARN: Fallback Windows source IP detection failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    return [PSCustomObject]@{
        IpAddress = $null
        Method = "unavailable"
    }
}

function Assert-LabTargets {
    try {
        $web = [Uri]$WebBase
        $auth = [Uri]$AuthBase
    }
    catch {
        throw "Refusing to run: WebBase and AuthBase must be valid HTTP URLs. WebBase=$WebBase AuthBase=$AuthBase"
    }

    if ($web.Scheme -ne "http") {
        throw "Refusing to run: WebBase must use http for this lab. Received: $WebBase"
    }

    if ($auth.Scheme -ne "http") {
        throw "Refusing to run: AuthBase must use http for this lab. Received: $AuthBase"
    }

    if (-not (Test-LabPrivateIPv4 -TargetHostName $web.Host)) {
        throw "Refusing to run: WebBase host must be a private IPv4 lab address. Received: $WebBase"
    }

    if (-not (Test-LabPrivateIPv4 -TargetHostName $auth.Host)) {
        throw "Refusing to run: AuthBase host must be a private IPv4 lab address. Received: $AuthBase"
    }

    if ($web.Port -ne -1 -and $web.Port -ne 80) {
        throw "Refusing to run: WebBase must use default HTTP port 80 for this lab. Received: $WebBase"
    }

    if ($auth.Port -ne 8000) {
        throw "Refusing to run: AuthBase must use port 8000 for this lab. Received: $AuthBase"
    }
}

function Join-LabUrl {
    param(
        [string]$Base,
        [string]$Path
    )

    if (-not $Path.StartsWith("/")) {
        $Path = "/$Path"
    }

    return "$($Base.TrimEnd("/"))$Path"
}

function Get-EncodedSearchPath {
    param([string]$Query)
    return "/search?q=$([System.Uri]::EscapeDataString($Query))"
}

function Start-LabDelay {
    if ($DelayMs -le 0) {
        return
    }

    $sleepMs = $DelayMs
    if ($Randomize -and $script:Rng) {
        $min = [Math]::Max(50, [int]($DelayMs * 0.6))
        $max = [Math]::Max($min + 1, [int]($DelayMs * 1.5))
        $sleepMs = $script:Rng.Next($min, $max)
    }

    Start-Sleep -Milliseconds $sleepMs
}

function Shuffle-Items {
    param([object[]]$Items)

    $itemsList = @($Items)
    if (-not $Randomize -or -not $script:Rng -or $itemsList.Count -le 1) {
        return $itemsList
    }

    for ($i = $itemsList.Count - 1; $i -gt 0; $i--) {
        $j = $script:Rng.Next(0, $i + 1)
        $temp = $itemsList[$i]
        $itemsList[$i] = $itemsList[$j]
        $itemsList[$j] = $temp
    }

    return $itemsList
}

function Select-RandomItem {
    param([object[]]$Items)

    $itemsList = @($Items)
    if ($itemsList.Count -eq 0) {
        return $null
    }

    if (-not $Randomize -or -not $script:Rng) {
        return $itemsList[0]
    }

    return $itemsList[$script:Rng.Next(0, $itemsList.Count)]
}

function Get-RandomUserAgent {
    $agents = @(
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) XDRLab/2.0",
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) SOCAnalystPortal/1.4",
        "CodingFest-XDR-Lab/2.0",
        "PowerShell-LabClient/7.4",
        "ServiceHealthCheck/1.0"
    )

    return [string](Select-RandomItem $agents)
}

function Get-RequestHeaders {
    return @{
        "User-Agent" = Get-RandomUserAgent
        "X-Lab-Run-Id" = $RunId
        "X-Lab-Scenario" = $Scenario
    }
}

function Get-NormalSearchTerm {
    $terms = @(
        "dashboard",
        "report",
        "help",
        "settings",
        "profile",
        "incident",
        "case",
        "alert",
        "documentation",
        "user guide",
        "telemetry",
        "service status",
        "security overview",
        "audit view",
        "asset inventory",
        "timeline",
        "investigation",
        "normal query",
        "project update",
        "login help"
    )

    return [string](Select-RandomItem $terms)
}

function Get-RouteFamily {
    param([string]$Path)

    if ($Path -eq "/") { return "homepage" }
    if ($Path -eq "/health") { return "health" }
    if ($Path -eq "/login") { return "login" }
    if ($Path -like "/search*") { return "search" }
    return "other"
}

function Get-BenignRequestTargetCount {
    switch ($Intensity) {
        "Low" { return Select-CountInRange -Minimum 8 -Maximum 15 }
        "Medium" { return Select-CountInRange -Minimum 16 -Maximum 30 }
        "High" { return Select-CountInRange -Minimum 31 -Maximum 45 }
    }
}

function Get-DosRequestCount {
    param([string]$ScenarioName)

    if ($ScenarioName -eq "AttackerHostLightDos") {
        switch ($Intensity) {
            "Low" { return Select-CountInRange -Minimum 20 -Maximum 20 }
            "Medium" { return Select-CountInRange -Minimum 21 -Maximum 35 }
            "High" { return Select-CountInRange -Minimum 36 -Maximum 50 }
        }
    }

    switch ($Intensity) {
        "Low" { return Select-CountInRange -Minimum 10 -Maximum 20 }
        "Medium" { return Select-CountInRange -Minimum 21 -Maximum 35 }
        "High" { return Select-CountInRange -Minimum 36 -Maximum 50 }
    }
}

function Get-DosVariant {
    $variants = @(
        "search_endpoint_pressure",
        "health_endpoint_pressure",
        "homepage_refresh_pressure",
        "mixed_endpoint_pressure",
        "login_page_pressure",
        "slow_low_rate_pressure",
        "short_spike_pressure",
        "sustained_low_pressure"
    )

    if ($Randomize) {
        return [string](Select-RandomItem $variants)
    }

    return "mixed_endpoint_pressure"
}

function Get-DosPathForVariant {
    param(
        [string]$Variant,
        [int]$Index
    )

    switch ($Variant) {
        "search_endpoint_pressure" { return Get-EncodedSearchPath -Query (Get-NormalSearchTerm) }
        "health_endpoint_pressure" { return "/health" }
        "homepage_refresh_pressure" { return "/" }
        "login_page_pressure" { return "/login" }
        "slow_low_rate_pressure" {
            if ($Index % 4 -eq 0) { return "/health" }
            if ($Index % 4 -eq 1) { return "/" }
            return Get-EncodedSearchPath -Query (Get-NormalSearchTerm)
        }
        "short_spike_pressure" {
            if ($Index % 5 -eq 0) { return "/" }
            return Get-EncodedSearchPath -Query (Get-NormalSearchTerm)
        }
        "sustained_low_pressure" {
            if ($Index % 6 -eq 0) { return "/health" }
            if ($Index % 6 -eq 1) { return "/login" }
            return Get-EncodedSearchPath -Query (Get-NormalSearchTerm)
        }
        default {
            $paths = @("/", "/health", "/login", (Get-EncodedSearchPath -Query (Get-NormalSearchTerm)))
            return [string](Select-RandomItem $paths)
        }
    }
}

function Start-DosPacingDelay {
    param(
        [string]$Variant,
        [int]$Index
    )

    if ($Variant -eq "short_spike_pressure") {
        Start-Sleep -Milliseconds (Select-CountInRange -Minimum 40 -Maximum 120)
        return
    }

    if ($Variant -eq "slow_low_rate_pressure" -or $Variant -eq "sustained_low_pressure") {
        Start-Sleep -Milliseconds (Select-CountInRange -Minimum ([Math]::Max(200, $DelayMs)) -Maximum ([Math]::Max(600, $DelayMs * 2)))
        return
    }

    if ($Variant -eq "mixed_endpoint_pressure" -and $Index -gt 0 -and $Index % 12 -eq 0) {
        Start-Sleep -Milliseconds (Select-CountInRange -Minimum 800 -Maximum 1500)
        return
    }

    Start-LabDelay
}

function Invoke-LabGet {
    param(
        [string]$Path,
        [string]$Description = $Path,
        [switch]$AbortAfterThreeConsecutiveFailures,
        [switch]$NoDelay
    )

    $url = Join-LabUrl -Base $WebBase -Path $Path
    Write-Step "GET $Description"
    Add-ActionCount "GET $Path"
    Add-ActualRequestCount

    $requestPassed = $true
    try {
        Invoke-WebRequest -Uri $url -Method GET -Headers (Get-RequestHeaders) -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop | Out-Null
    }
    catch {
        $requestPassed = $false
        Write-Host "  WARN: GET failed but run will continue: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    if ($AbortAfterThreeConsecutiveFailures) {
        if ($requestPassed) {
            $script:ConsecutiveRequestFailures = 0
        }
        else {
            $script:ConsecutiveRequestFailures++
            if ($script:ConsecutiveRequestFailures -ge 3) {
                throw "Aborting AttackerHostLightDos after 3 consecutive request failures."
            }
        }
    }

    if (-not $NoDelay) {
        Start-LabDelay
    }
}

function Invoke-Search {
    param(
        [string]$Query,
        [string]$Description = "search",
        [switch]$AbortAfterThreeConsecutiveFailures,
        [switch]$NoDelay
    )

    Invoke-LabGet -Path (Get-EncodedSearchPath -Query $Query) -Description "$Description query='$Query'" -AbortAfterThreeConsecutiveFailures:$AbortAfterThreeConsecutiveFailures -NoDelay:$NoDelay
}

function Invoke-WebLogin {
    param(
        [string]$Username,
        [string]$Password,
        [string]$Description = "web login"
    )

    $url = Join-LabUrl -Base $WebBase -Path "/login"
    Write-Step "POST /login $Description username=$Username"
    Add-ActionCount "POST /login"
    Add-ActualRequestCount

    try {
        Invoke-WebRequest `
            -Uri $url `
            -Method POST `
            -Headers (Get-RequestHeaders) `
            -Body @{ username = $Username; password = $Password } `
            -UseBasicParsing `
            -TimeoutSec 15 `
            -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Host "  WARN: login request failed but expected failed credentials will not stop the run: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    Start-LabDelay
}

function Test-LabHealth {
    Write-Step "Preflight Auth health"
    try {
        $authHealth = Invoke-RestMethod -Uri (Join-LabUrl -Base $AuthBase -Path "/health") -Method GET -TimeoutSec 10 -ErrorAction Stop
        if ($authHealth.status -ne "ok") {
            throw "Unexpected Auth health response: $($authHealth | ConvertTo-Json -Compress)"
        }
    }
    catch {
        Write-Host "Auth health check failed. No scenario telemetry will be generated." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        return $false
    }

    Write-Step "Preflight Web health"
    try {
        $webHealth = Invoke-RestMethod -Uri (Join-LabUrl -Base $WebBase -Path "/health") -Method GET -TimeoutSec 10 -ErrorAction Stop
        if ($webHealth.status -ne "ok") {
            throw "Unexpected Web health response: $($webHealth | ConvertTo-Json -Compress)"
        }
    }
    catch {
        Write-Host "Web health check failed. No scenario telemetry will be generated." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        return $false
    }

    return $true
}

function Get-MainLabel {
    param([string]$ScenarioName)

    switch ($ScenarioName) {
        "Benign" { "Benign" }
        "UnauthorizedAccess" { "Unauthorized_Access" }
        "SqliProbe" { "Data_Breach" }
        "LightDos" { "DoS_DDoS" }
        "AttackerHostLightDos" { "DoS_DDoS" }
        "MultiSourceLightDos" { "DoS_DDoS" }
        "MixedDemo" { "Mixed_Demo" }
    }
}

function Get-ExpectedEventTypes {
    param([string]$ScenarioName)

    switch ($ScenarioName) {
        "Benign" { @("page_view", "search_query", "web_login_attempt", "login_success", "admin_route_access") }
        "UnauthorizedAccess" { @("page_view", "web_login_attempt", "login_failed", "login_success", "admin_route_access", "search_query") }
        "SqliProbe" { @("search_query", "suspicious_query", "admin_route_access_denied") }
        "LightDos" { @("page_view", "search_query", "request_completed", "nginx_access") }
        "AttackerHostLightDos" { @("page_view", "search_query", "request_completed", "nginx_access") }
        "MultiSourceLightDos" { @("page_view", "search_query", "request_completed", "nginx_access") }
        "MixedDemo" { @("page_view", "search_query", "web_login_attempt", "login_failed", "login_success", "suspicious_query", "admin_route_access", "admin_route_access_denied", "nginx_access") }
    }
}

function Get-ExpectedMlFeatures {
    param([string]$ScenarioName)

    switch ($ScenarioName) {
        "Benign" {
            @(
                "low_failed_login_count",
                "normal_search_query_count",
                "hard_negative_high_activity_count",
                "repeated_endpoint_benign_count",
                "successful_login_count",
                "no_suspicious_query_count",
                "no_success_after_large_failure_burst"
            )
        }
        "UnauthorizedAccess" {
            @(
                "failed_login_count",
                "failed_login_rate",
                "unknown_user_count",
                "unique_username_count",
                "success_after_failures",
                "admin_access_after_success",
                "same_source_repeated_attempts"
            )
        }
        "SqliProbe" {
            @(
                "suspicious_query_count",
                "sqli_pattern_count",
                "union_select_count",
                "information_schema_count",
                "comment_marker_count",
                "normal_search_before_after"
            )
        }
        "LightDos" {
            @(
                "request_count",
                "request_rate",
                "repeated_path_count",
                "same_source_request_ratio",
                "status_code_distribution",
                "response_time_ms",
                "health_check_latency_ms",
                "request_duration_ms",
                "no_destructive_service_outage_required"
            )
        }
        "AttackerHostLightDos" {
            @(
                "request_count",
                "request_rate",
                "repeated_path_count",
                "same_source_request_ratio",
                "observed_source_count",
                "status_code_distribution",
                "response_time_ms",
                "health_check_latency_ms",
                "request_duration_ms",
                "single_source_dos_evidence",
                "no_destructive_service_outage_required"
            )
        }
        "MultiSourceLightDos" {
            @(
                "request_count",
                "request_rate",
                "repeated_path_count",
                "observed_source_count",
                "top_source_ip_ratio",
                "distributed_evidence_confirmed",
                "status_code_distribution",
                "response_time_ms",
                "health_check_latency_ms",
                "request_duration_ms"
            )
        }
        "MixedDemo" {
            @(
                "multi_class_event_window",
                "cross_source_correlation",
                "mixed_labels_not_clean_for_supervised_training"
            )
        }
    }
}

function Get-FailureCount {
    switch ($Intensity) {
        "Low" {
            if ($Randomize) { return $script:Rng.Next(3, 6) }
            return 4
        }
        "Medium" {
            if ($Randomize) { return $script:Rng.Next(6, 11) }
            return 8
        }
        "High" {
            if ($Randomize) { return $script:Rng.Next(11, 16) }
            return 13
        }
    }
}

function Get-SqliPayloadCount {
    switch ($Intensity) {
        "Low" {
            if ($Randomize) { return $script:Rng.Next(2, 4) }
            return 2
        }
        "Medium" {
            if ($Randomize) { return $script:Rng.Next(3, 6) }
            return 4
        }
        "High" {
            if ($Randomize) { return $script:Rng.Next(4, 7) }
            return 6
        }
    }
}

function Get-LightDosRequestCount {
    return Get-DosRequestCount -ScenarioName "LightDos"
}

function Get-AttackerHostLightDosRequestCount {
    return Get-DosRequestCount -ScenarioName "AttackerHostLightDos"
}

function Get-AttackerHostDurationCapSeconds {
    switch ($Intensity) {
        "Low" { return 15 }
        "Medium" { return 25 }
        "High" { return 35 }
    }
}

function Invoke-BenignScenario {
    param([int]$Round)

    $variantOptions = @(
        "normal_browsing",
        "heavy_search_benign",
        "healthcheck_heavy_benign",
        "repeated_endpoint_benign",
        "mixed_user_journey_benign",
        "benign_burst_without_attack"
    )
    $sublabel = if ($Randomize) { Select-RandomItem $variantOptions } else { "normal_browsing" }
    $activityLevel = switch ($sublabel) {
        "normal_browsing" { "baseline" }
        "heavy_search_benign" { "hard_negative_search_activity" }
        "healthcheck_heavy_benign" { "hard_negative_healthcheck_activity" }
        "repeated_endpoint_benign" { "hard_negative_repeated_endpoint_activity" }
        "mixed_user_journey_benign" { "hard_negative_mixed_user_journey" }
        "benign_burst_without_attack" { "hard_negative_benign_burst" }
    }

    $script:TargetEndpointFamily = "web_app_auth_and_health"
    $script:ExpectedHardNegative = ($sublabel -ne "normal_browsing")
    Write-Host "`nRound $Round/$Rounds - Benign ($sublabel, activity=$activityLevel)" -ForegroundColor Cyan

    $targetCount = Get-BenignRequestTargetCount
    Add-PlannedRequestCount -Count $targetCount

    $roundStartActual = [int]$script:ActualRequestCount

    Invoke-LabGet -Path "/" -Description "normal homepage"
    Invoke-LabGet -Path "/login" -Description "normal login page"

    if ($ActorProfile -eq "careless_user" -and $sublabel -ne "normal_browsing" -and ($script:Rng.Next(0, 3) -eq 1)) {
        $script:BenignNoise = $true
        Invoke-WebLogin -Username "admin" -Password "AdminPass123" -Description "mild mistyped benign login"
    }

    $sent = [int]$script:ActualRequestCount - $roundStartActual
    while ($sent -lt $targetCount) {
        $pathFamily = switch ($sublabel) {
            "normal_browsing" { Select-RandomItem @("search", "homepage", "login") }
            "heavy_search_benign" { Select-RandomItem @("search", "search", "search", "homepage", "login") }
            "healthcheck_heavy_benign" { Select-RandomItem @("health", "health", "health", "homepage", "search") }
            "repeated_endpoint_benign" { Select-RandomItem @("homepage", "homepage", "login", "search") }
            "mixed_user_journey_benign" { Select-RandomItem @("health", "homepage", "search", "login", "admin") }
            "benign_burst_without_attack" { Select-RandomItem @("search", "search", "homepage", "health") }
        }

        switch ($pathFamily) {
            "health" { Invoke-LabGet -Path "/health" -Description "benign service status check" }
            "homepage" { Invoke-LabGet -Path "/" -Description "benign repeated homepage load" }
            "login" { Invoke-LabGet -Path "/login" -Description "benign login page revisit" }
            "admin" {
                Invoke-WebLogin -Username "admin" -Password "AdminPass123!" -Description "successful normal admin login"
                Invoke-LabGet -Path "/admin?user=admin" -Description "normal admin route"
            }
            default { Invoke-Search -Query (Get-NormalSearchTerm) -Description "normal benign search" }
        }

        $sent = [int]$script:ActualRequestCount - $roundStartActual
    }

    if ($sublabel -eq "mixed_user_journey_benign" -or $sublabel -eq "normal_browsing") {
        Invoke-WebLogin -Username "admin" -Password "AdminPass123!" -Description "successful normal admin login"
        Invoke-LabGet -Path "/admin?user=admin" -Description "admin route as admin"
    }

    $script:RoundSublabels.Add($sublabel)
    $script:ScenarioVariants.Add($sublabel)
    $script:BenignActivityLevels.Add($activityLevel)
}

function Invoke-UnauthorizedAccessScenario {
    param([int]$Round)

    $subScenarioOptions = @("ato_progression", "brute_force_failed_only", "credential_stuffing", "success_after_failures")
    $sublabel = if ($Randomize) { Select-RandomItem $subScenarioOptions } else { "ato_progression" }
    $script:TargetEndpointFamily = "web_app_auth_api"
    Write-Host "`nRound $Round/$Rounds - UnauthorizedAccess ($sublabel)" -ForegroundColor Cyan

    $passwords = @(
        "Password123!",
        "Admin123!",
        "Winter2026!",
        "Welcome1!",
        "Company2026!",
        "AdminPass123",
        "P@ssw0rd!",
        "CodingFest2026!"
    )

    $unknownUsers = @("root", "administrator", "backup", "postgres", "service")
    $stuffingUsers = @("admin", "analyst", "user1")
    if ($Randomize) {
        $unknownUsers = Shuffle-Items $unknownUsers
        $passwords = Shuffle-Items $passwords
        $stuffingUsers = Shuffle-Items $stuffingUsers
    }

    Invoke-LabGet -Path "/login" -Description "open login before identity abuse"

    if ($sublabel -eq "credential_stuffing") {
        foreach ($username in $stuffingUsers) {
            $password = Select-RandomItem $passwords
            Invoke-WebLogin -Username $username -Password $password -Description "credential stuffing failed login"
        }
    }
    else {
        $failedCount = Get-FailureCount
        for ($i = 0; $i -lt $failedCount; $i++) {
            $password = $passwords[$i % $passwords.Count]
            Invoke-WebLogin -Username "admin" -Password $password -Description "admin failed burst $($i + 1)/$failedCount"
        }
    }

    foreach ($unknownUser in $unknownUsers) {
        $password = Select-RandomItem $passwords
        Invoke-WebLogin -Username $unknownUser -Password $password -Description "unknown-user probe"
    }

    if ($Randomize -and $sublabel -ne "brute_force_failed_only") {
        foreach ($extraUser in (Shuffle-Items @("analyst", "user1") | Select-Object -First 1)) {
            Invoke-WebLogin -Username $extraUser -Password (Select-RandomItem $passwords) -Description "extra known-user failed login"
        }
    }

    if ($sublabel -eq "success_after_failures" -or $sublabel -eq "ato_progression") {
        Invoke-WebLogin -Username "admin" -Password "AdminPass123!" -Description "successful admin login after failures"
    }

    if ($sublabel -eq "ato_progression") {
        Invoke-LabGet -Path "/admin?user=admin" -Description "admin route after success"
        Invoke-Search -Query "user management" -Description "normal-looking post-login search"
    }
    elseif ($sublabel -eq "success_after_failures") {
        Invoke-Search -Query "account settings" -Description "normal-looking post-login search"
    }

    $script:RoundSublabels.Add($sublabel)
    $script:ScenarioVariants.Add($sublabel)
}

function Invoke-SqliProbeScenario {
    param([int]$Round)

    $subScenarioOptions = @("basic_sqli_probe", "union_select_probe", "information_schema_probe", "comment_bypass_probe", "mixed_sqli_probe")
    $sublabel = if ($Randomize) { Select-RandomItem $subScenarioOptions } else { "mixed_sqli_probe" }
    $script:TargetEndpointFamily = "web_app_search"
    Write-Host "`nRound $Round/$Rounds - SqliProbe ($sublabel)" -ForegroundColor Cyan

    $payloadMap = @{
        basic_sqli_probe = @("' OR '1'='1", "' OR 1=1 --")
        union_select_probe = @("UNION SELECT username,password FROM users", "1 UNION SELECT null,null")
        information_schema_probe = @("information_schema.tables")
        comment_bypass_probe = @("admin'--", "' OR 1=1 --")
        mixed_sqli_probe = @(
            "' OR '1'='1",
            "' OR 1=1 --",
            "admin'--",
            "UNION SELECT username,password FROM users",
            "1 UNION SELECT null,null",
            "information_schema.tables",
            "; DROP TABLE users;"
        )
    }

    Invoke-Search -Query "report" -Description "normal search before suspicious probes"

    $payloads = @($payloadMap[$sublabel])
    if ($sublabel -ne "mixed_sqli_probe" -and (Get-SqliPayloadCount) -gt $payloads.Count) {
        $payloads += @($payloadMap["mixed_sqli_probe"])
    }

    $payloadCount = [Math]::Min((Get-SqliPayloadCount), $payloads.Count)
    foreach ($payload in (Shuffle-Items $payloads | Select-Object -First $payloadCount)) {
        Invoke-Search -Query $payload -Description "safe SQLi-style search string"
    }

    Invoke-Search -Query "search documentation" -Description "normal search after suspicious probes"

    if ($Randomize -and ($script:Rng.Next(0, 2) -eq 1)) {
        Invoke-LabGet -Path "/admin?user=guest" -Description "optional guest admin denied check"
    }

    $script:RoundSublabels.Add($sublabel)
    $script:ScenarioVariants.Add($sublabel)
}

function Invoke-LightDosScenario {
    param([int]$Round)

    $sublabel = Get-DosVariant
    $requestCount = [Math]::Min((Get-LightDosRequestCount), $script:LightDosRequestCap)
    Add-PlannedRequestCount -Count $requestCount
    $script:TargetEndpointFamily = "web_app_service_stress"
    $script:RequestCap = $script:LightDosRequestCap
    Write-Host "`nRound $Round/$Rounds - LightDos ($sublabel, $requestCount requests max)" -ForegroundColor Cyan
    $script:TargetPaths = @("/", "/health", "/search?q=<normal-term>", "/login")

    $sent = 0
    Invoke-LabGet -Path "/health" -Description "service health before light pressure" -NoDelay
    Start-DosPacingDelay -Variant $sublabel -Index $sent
    $sent++

    if ($sent -lt $requestCount) {
        Invoke-LabGet -Path "/" -Description "homepage before light pressure" -NoDelay
        Start-DosPacingDelay -Variant $sublabel -Index $sent
        $sent++
    }

    while ($sent -lt $requestCount) {
        $path = Get-DosPathForVariant -Variant $sublabel -Index $sent
        if ($path -like "/search?q=*") {
            $query = [System.Uri]::UnescapeDataString($path.Substring("/search?q=".Length))
            Invoke-Search -Query $query -Description "rate-limited service-pressure search" -NoDelay
        }
        else {
            Invoke-LabGet -Path $path -Description "rate-limited service pressure $path" -NoDelay
        }

        Start-DosPacingDelay -Variant $sublabel -Index $sent
        $sent++
    }

    $script:RoundSublabels.Add($sublabel)
    $script:ScenarioVariants.Add($sublabel)
}

function Invoke-AttackerHostLightDosScenario {
    param([int]$Round)

    $sublabel = Get-DosVariant
    $script:RequestCap = $script:AttackerHostRequestCap
    $requestCount = [Math]::Min((Get-AttackerHostLightDosRequestCount), $script:RequestCap)
    $durationCapSeconds = Get-AttackerHostDurationCapSeconds
    Add-PlannedRequestCount -Count $requestCount
    $script:DurationCapSeconds = $durationCapSeconds
    $script:TargetEndpointFamily = "web_app_single_source_service_stress"
    $script:TargetPaths = @(
        "/health",
        "/",
        "/search?q=<normal-term>",
        "/login"
    )
    $script:ConsecutiveRequestFailures = 0

    Write-Host "`nRound $Round/$Rounds - AttackerHostLightDos ($sublabel, $requestCount requests max, sequential single-source)" -ForegroundColor Cyan
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $sent = 0

    Invoke-LabGet -Path "/health" -Description "service health before Windows-host single-source pressure" -AbortAfterThreeConsecutiveFailures -NoDelay
    Start-DosPacingDelay -Variant $sublabel -Index $sent
    $sent++

    if ($sent -lt $requestCount) {
        Invoke-LabGet -Path "/" -Description "homepage before Windows-host single-source pressure" -AbortAfterThreeConsecutiveFailures -NoDelay
        Start-DosPacingDelay -Variant $sublabel -Index $sent
        $sent++
    }

    while ($sent -lt $requestCount) {
        if ($stopwatch.Elapsed.TotalSeconds -ge $durationCapSeconds) {
            Write-Host "  WARN: AttackerHostLightDos duration cap reached after $sent request(s)." -ForegroundColor Yellow
            break
        }

        $path = Get-DosPathForVariant -Variant $sublabel -Index $sent
        if ($path -like "/search?q=*") {
            $query = [System.Uri]::UnescapeDataString($path.Substring("/search?q=".Length))
            Invoke-Search -Query $query -Description "Windows-host single-source service-pressure search" -AbortAfterThreeConsecutiveFailures -NoDelay
        }
        else {
            Invoke-LabGet -Path $path -Description "Windows-host single-source service pressure $path" -AbortAfterThreeConsecutiveFailures -NoDelay
        }

        Start-DosPacingDelay -Variant $sublabel -Index $sent
        $sent++
    }

    $stopwatch.Stop()
    Write-Host "  Completed $sent request(s) in $([Math]::Round($stopwatch.Elapsed.TotalSeconds, 2)) second(s)." -ForegroundColor DarkGray
    $script:RoundSublabels.Add($sublabel)
    $script:ScenarioVariants.Add($sublabel)
}

function Get-MultipassSourceIp {
    param([string]$Instance)

    try {
        $output = & multipass exec $Instance -- bash -lc "ip -4 route get $(([Uri]$WebBase).Host) | awk '{for(i=1;i<=NF;i++) if(\$i==""src"") {print \$(i+1); exit}}'" 2>&1
        $ip = ([string]($output -join "`n")).Trim()
        if (Test-LabPrivateIPv4 -TargetHostName $ip) {
            return $ip
        }
    }
    catch {
        Write-Host "  WARN: Could not detect source IP for $Instance`: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    return $null
}

function Invoke-RemoteSourceGet {
    param(
        [string]$Instance,
        [string]$Path,
        [string]$Description
    )

    $url = Join-LabUrl -Base $WebBase -Path $Path
    Write-Step "GET $Description from $Instance"
    Add-ActionCount "REMOTE $Instance GET $Path"
    Add-ActualRequestCount

    try {
        & multipass exec $Instance -- curl -sS --max-time 10 -A "CodingFest-XDR-MultiSource/$RunId" $url 2>&1 | Out-Null
    }
    catch {
        Write-Host "  WARN: Remote source GET failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    Start-LabDelay
}

function Invoke-MultiSourceLightDosScenario {
    param([int]$Round)

    $configuredSources = @($SourceHosts | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
    if ($configuredSources.Count -lt $MinVisibleSources) {
        Write-Host "MultiSourceLightDos cannot run because fewer than $MinVisibleSources source host(s) were configured. SourceHosts=$($configuredSources -join ',')" -ForegroundColor Red
        exit 1
    }

    $allowedSources = @("windows", "auth-server", "web-server", "db-server")
    foreach ($source in $configuredSources) {
        if ($allowedSources -notcontains $source) {
            Write-Host "MultiSourceLightDos refusing unknown source host '$source'. Allowed: $($allowedSources -join ', ')." -ForegroundColor Red
            exit 1
        }
    }

    $sourceIps = New-Object System.Collections.Generic.List[string]
    foreach ($source in $configuredSources) {
        if ($source -eq "windows") {
            $sourceInfo = Get-WindowsSourceIpForTarget
            if (-not [string]::IsNullOrWhiteSpace($sourceInfo.IpAddress)) {
                $sourceIps.Add([string]$sourceInfo.IpAddress) | Out-Null
            }
        }
        else {
            $ip = Get-MultipassSourceIp -Instance $source
            if (-not [string]::IsNullOrWhiteSpace($ip)) {
                $sourceIps.Add($ip) | Out-Null
            }
        }
    }

    $visibleSourceCount = @($sourceIps.ToArray() | Select-Object -Unique).Count
    if ($RequireMultipleSources -and $visibleSourceCount -lt $MinVisibleSources) {
        Write-Host "MultiSourceLightDos cannot run because fewer than $MinVisibleSources visible source IPs are available. Detected=$($sourceIps.ToArray() -join ',')" -ForegroundColor Red
        exit 1
    }

    if ($visibleSourceCount -lt $MinVisibleSources) {
        Write-Host "MultiSourceLightDos cannot run because fewer than $MinVisibleSources visible source IPs are available. Detected=$($sourceIps.ToArray() -join ',')" -ForegroundColor Red
        exit 1
    }

    $sublabel = Get-DosVariant
    $script:RequestCap = [Math]::Min($TotalRequestCap, 60)
    $requestCount = [Math]::Min((Get-DosRequestCount -ScenarioName "MultiSourceLightDos"), $script:RequestCap)
    $requestCount = [Math]::Min($requestCount, ($MaxRequestsPerSource * $configuredSources.Count))
    Add-PlannedRequestCount -Count $requestCount
    $script:TargetEndpointFamily = "web_app_multi_source_service_stress"
    $script:TargetPaths = @("/", "/health", "/search?q=<normal-term>", "/login")
    $script:MultiSourceObservedSourceCount = $visibleSourceCount
    $script:MultiSourceSourceHosts = @($configuredSources)
    $script:MultiSourceSourceIps = @($sourceIps.ToArray() | Select-Object -Unique)

    Write-Host "`nRound $Round/$Rounds - MultiSourceLightDos ($sublabel, $requestCount requests max, sources=$($configuredSources -join ','))" -ForegroundColor Cyan

    for ($i = 0; $i -lt $requestCount; $i++) {
        $source = $configuredSources[$i % $configuredSources.Count]
        $path = Get-DosPathForVariant -Variant $sublabel -Index $i

        if ($source -eq "windows") {
            Invoke-LabGet -Path $path -Description "multi-source Windows service pressure $path" -NoDelay
            Start-DosPacingDelay -Variant $sublabel -Index $i
        }
        else {
            Invoke-RemoteSourceGet -Instance $source -Path $path -Description "multi-source service pressure $path"
        }
    }

    $script:RoundSublabels.Add($sublabel)
    $script:ScenarioVariants.Add($sublabel)
}

function Invoke-MixedDemoScenario {
    param([int]$Round)

    $sublabel = "mixed_dashboard_demo"
    $script:TargetEndpointFamily = "web_app_auth_api_search_service_stress"
    Write-Host "`nRound $Round/$Rounds - MixedDemo ($sublabel)" -ForegroundColor Cyan
    Write-Host "MixedDemo combines labels and is not clean supervised-training data." -ForegroundColor Yellow

    Invoke-LabGet -Path "/" -Description "mixed benign homepage"
    Invoke-LabGet -Path "/login" -Description "mixed benign login page"
    Invoke-Search -Query "security dashboard" -Description "mixed benign search"
    Invoke-WebLogin -Username "admin" -Password "AdminPass123!" -Description "mixed successful admin login"

    foreach ($password in @("Password123!", "Admin123!", "Winter2026!")) {
        Invoke-WebLogin -Username "admin" -Password $password -Description "mixed unauthorized failed login"
    }

    Invoke-WebLogin -Username "root" -Password "Password123!" -Description "mixed unknown-user probe"
    Invoke-WebLogin -Username "admin" -Password "AdminPass123!" -Description "mixed success after failures"
    Invoke-LabGet -Path "/admin?user=admin" -Description "mixed admin access after success"

    foreach ($payload in @("' OR '1'='1", "UNION SELECT username,password FROM users")) {
        Invoke-Search -Query $payload -Description "mixed safe SQLi-style search"
    }

    for ($i = 0; $i -lt 10; $i++) {
        Invoke-Search -Query "burst-mixed-$Round-$i" -Description "mixed light request-volume search"
    }

    $script:RoundSublabels.Add($sublabel)
    $script:ScenarioVariants.Add($sublabel)
}

function Get-SafetyNotes {
    param([string]$ScenarioName)

    $notes = @(
        "Targets are restricted to private IPv4 lab HTTP endpoints: WebBase on port 80 and AuthBase on port 8000.",
        "No direct database attack behavior is performed.",
        "Expected failed logins are treated as controlled telemetry, not script errors."
    )

    if ($ScenarioName -eq "SqliProbe" -or $ScenarioName -eq "MixedDemo") {
        $notes += "SQLi-style strings are sent only to the safe /search route as search input."
    }

    if ($ScenarioName -eq "LightDos" -or $ScenarioName -eq "AttackerHostLightDos" -or $ScenarioName -eq "MultiSourceLightDos" -or $ScenarioName -eq "MixedDemo") {
        $notes += "DoS-style activity is sequential, respects DelayMs, and uses bounded Low/Medium request ranges only."
    }

    if ($ScenarioName -eq "AttackerHostLightDos") {
        $notes += "AttackerHostLightDos is Windows-host single-source application-layer DoS/service-stress telemetry. It is not DDoS."
        $notes += "No parallel jobs or runspaces are used. The run aborts after 3 consecutive request failures."
    }

    if ($ScenarioName -eq "MultiSourceLightDos") {
        $notes += "MultiSourceLightDos requires multiple real lab source hosts and refuses to run when fewer than MinVisibleSources visible source IPs are detected."
        $notes += "No source IP spoofing, amplification, packet capture, external targets, or destructive outage goal is used."
    }

    if ($ScenarioName -eq "MixedDemo") {
        $notes += "MixedDemo is useful for dashboard demos and correlation testing, not clean supervised labels."
    }

    return $notes
}

function Get-TrainingNotes {
    param([string]$ScenarioName)

    switch ($ScenarioName) {
        "Benign" {
            @(
                "Use as baseline normal-user activity.",
                "If benign_noise is true, failed_login_count may be non-zero but still represents ordinary user error.",
                "Hard-negative benign variants intentionally create repeated but legitimate user activity without SQLi strings or attacker wording."
            )
        }
        "UnauthorizedAccess" {
            @(
                "Use for Unauthorized_Access windows with repeated failures, unknown users, and possible success-after-failures.",
                "Good candidate features include login rate, username diversity, and admin access after successful login."
            )
        }
        "SqliProbe" {
            @(
                "Use for Data_Breach preparation windows based on suspicious_query evidence.",
                "Payloads are labels for web input behavior only; they are not database exploitation."
            )
        }
        "LightDos" {
            @(
                "Use for DoS request-volume windows without requiring service outage.",
                "Keep DelayMs and request caps in exported metadata for later request-rate feature calculation."
            )
        }
        "AttackerHostLightDos" {
            @(
                "Use for Windows-host single-source DoS_HTTP_Flood/service-stress windows.",
                "Do not label as DDoS unless future victim logs show multiple visible source IPs."
            )
        }
        "MultiSourceLightDos" {
            @(
                "Use only when victim logs confirm multiple visible source IPs.",
                "Ground truth still comes from controlled run metadata; Wazuh alerts are evidence context, not labels."
            )
        }
        "MixedDemo" {
            @(
                "Use for dashboard, Wazuh collection, and correlation demos.",
                "Do not use as a clean single-label supervised training sample."
            )
        }
    }
}

function Write-RunMetadata {
    param(
        [datetime]$StartTimeUtc,
        [datetime]$EndTimeUtc
    )

    $metadataDirectory = Split-Path -Path $OutputMetadataPath -Parent
    if ([string]::IsNullOrWhiteSpace($metadataDirectory)) {
        $metadataDirectory = "."
    }

    New-Item -ItemType Directory -Force -Path $metadataDirectory | Out-Null

    $metadataSublabel = Get-DistinctSummary -Values $script:RoundSublabels -Default "not_applicable"
    $scenarioVariant = Get-DistinctSummary -Values $script:ScenarioVariants -Default $metadataSublabel
    $benignActivityLevel = Get-DistinctSummary -Values $script:BenignActivityLevels -Default "not_applicable"
    $mainLabel = Get-MainLabel -ScenarioName $Scenario
    $plannedRequestCount = if ($null -ne $script:PlannedRequestCount) { [int]$script:PlannedRequestCount } else { [int]$script:ActualRequestCount }
    $targetEndpointFamily = if (-not [string]::IsNullOrWhiteSpace($script:TargetEndpointFamily)) { $script:TargetEndpointFamily } else { "web_app" }

    $metadata = [ordered]@{
        run_id = $RunId
        scenario = $Scenario
        main_label = $mainLabel
        sublabel = $metadataSublabel
        scenario_variant = $scenarioVariant
        actor_profile = $ActorProfile
        intensity = $Intensity
        benign_activity_level = $benignActivityLevel
        generator_version = $script:GeneratorVersion
        planned_request_count = $plannedRequestCount
        actual_request_count = [int]$script:ActualRequestCount
        safety_limit_applied = [bool]$script:SafetyLimitApplied
        safety_limit_reasons = @($script:SafetyLimitReasons.ToArray())
        request_cap = $script:RequestCap
        target_endpoint_family = $targetEndpointFamily
        start_time_utc = $StartTimeUtc.ToString("o")
        end_time_utc = $EndTimeUtc.ToString("o")
        targets = [ordered]@{
            web_base = $WebBase
            auth_base = $AuthBase
        }
        parameters = [ordered]@{
            rounds = $Rounds
            delay_ms = $DelayMs
            randomize = [bool]$Randomize
            output_metadata_path = $OutputMetadataPath
        }
        random_seed = $script:RandomSeed
        intended_event_types = Get-ExpectedEventTypes -ScenarioName $Scenario
        expected_log_sources = $ExpectedLogSourcesByScenario[$Scenario]
        expected_ml_features = Get-ExpectedMlFeatures -ScenarioName $Scenario
        safety_notes = Get-SafetyNotes -ScenarioName $Scenario
        training_notes = Get-TrainingNotes -ScenarioName $Scenario
        suitable_for_clean_supervised_training = ($Scenario -ne "MixedDemo")
        benign_noise = $script:BenignNoise
        expected_hard_negative = [bool]$script:ExpectedHardNegative
        action_counts = $script:ActionCounts
    }

    if ($Scenario -eq "MixedDemo") {
        $metadata["mixed_demo_warning"] = "MixedDemo is useful for dashboard demos and correlation testing, not clean supervised model training, because multiple incident classes are mixed in one run."
    }

    if ($Scenario -eq "AttackerHostLightDos") {
        $metadata["attacker_host_type"] = "windows_host"
        $metadata["attacker_source_ip"] = $script:AttackerSourceIp
        $metadata["target_web_base"] = $WebBase
        $metadata["traffic_tool"] = "PowerShell Invoke-WebRequest"
        $metadata["attack_mode"] = "DoS_HTTP_Flood"
        $metadata["distributed"] = $false
        $metadata["source_count"] = 1
        $metadata["expected_source_count"] = 1
        $metadata["expected_distributed"] = $false
        $metadata["concurrency"] = 1
        $metadata["duration_cap_seconds"] = $script:DurationCapSeconds
        $metadata["target_paths"] = @($script:TargetPaths)
        $metadata["source_ip_detection_method"] = $script:SourceIpDetectionMethod
    }

    if ($Scenario -eq "MultiSourceLightDos") {
        $metadata["target_web_base"] = $WebBase
        $metadata["traffic_tool"] = "PowerShell Invoke-WebRequest and controlled multipass curl"
        $metadata["attack_mode"] = "Distributed_DoS_HTTP_Flood"
        $metadata["distributed"] = ($script:MultiSourceObservedSourceCount -ge $MinVisibleSources)
        $metadata["expected_source_count"] = $MinVisibleSources
        $metadata["expected_distributed"] = $true
        $metadata["observed_source_count"] = $script:MultiSourceObservedSourceCount
        $metadata["source_hosts"] = @($script:MultiSourceSourceHosts)
        $metadata["source_ips"] = @($script:MultiSourceSourceIps)
        $metadata["source_count"] = $script:MultiSourceObservedSourceCount
        $metadata["source_ip_detection_method"] = "windows_udp_route_and_multipass_ip_route"
        $metadata["multi_source_mode"] = $MultiSourceMode
        $metadata["min_visible_sources"] = $MinVisibleSources
        $metadata["max_requests_per_source"] = $MaxRequestsPerSource
        $metadata["total_request_cap"] = $TotalRequestCap
        $metadata["target_paths"] = @($script:TargetPaths)
        $metadata["safety_notes"] += "distributed=true means configured source IP discovery found at least MinVisibleSources before generation; verification must still confirm multiple visible source IPs in victim logs."
    }

    $metadata | ConvertTo-Json -Depth 8 | Set-Content -Path $OutputMetadataPath -Encoding UTF8
    return $metadata
}

try {
    Assert-LabTargets
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

if (($Scenario -eq "AttackerHostLightDos" -or $Scenario -eq "MultiSourceLightDos") -and $Rounds -ne 1) {
    Write-Host "Refusing to run $Scenario with Rounds=$Rounds. Use exactly one round so the per-run request cap is never exceeded." -ForegroundColor Red
    exit 1
}

if (-not $RunId) {
    $RunId = "run-$((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'))-$Scenario"
}

if ($Scenario -eq "AttackerHostLightDos") {
    $sourceInfo = Get-WindowsSourceIpForTarget
    $script:AttackerSourceIp = $sourceInfo.IpAddress
    $script:SourceIpDetectionMethod = $sourceInfo.Method
}

if ($Scenario -eq "MultiSourceLightDos" -and -not $PSBoundParameters.ContainsKey("SourceHosts")) {
    Write-Host "MultiSourceLightDos is guarded. Pass -SourceHosts with at least two real lab sources, for example windows,auth-server. No traffic was generated." -ForegroundColor Red
    exit 1
}

if ($Randomize) {
    $script:RandomSeed = [Math]::Abs([Guid]::NewGuid().GetHashCode())
    $script:Rng = [System.Random]::new($script:RandomSeed)
}
else {
    $script:RandomSeed = Get-StableSeed -Text "$RunId|$Scenario|$Intensity|$ActorProfile|$Rounds"
    $script:Rng = [System.Random]::new($script:RandomSeed)
}

Write-Host "============================================================"
Write-Host "Coding Fest 2026 XDR Controlled Telemetry Generator"
Write-Host "============================================================"
Write-Host "RunId:        $RunId"
Write-Host "Scenario:     $Scenario"
Write-Host "Label:        $(Get-MainLabel -ScenarioName $Scenario)"
Write-Host "ActorProfile: $ActorProfile"
Write-Host "Intensity:    $Intensity"
Write-Host "Rounds:       $Rounds"
Write-Host "DelayMs:      $DelayMs"
Write-Host "WebBase:      $WebBase"
Write-Host "AuthBase:     $AuthBase"
if ($Scenario -eq "AttackerHostLightDos") {
    Write-Host "Attacker IP:  $($script:AttackerSourceIp)"
    Write-Host "IP detection: $($script:SourceIpDetectionMethod)"
    Write-Host "Classification: Windows-host single-source DoS (not DDoS)" -ForegroundColor Yellow
}

if ($Scenario -eq "MultiSourceLightDos") {
    Write-Host "MultiSourceMode: $MultiSourceMode"
    Write-Host "SourceHosts:     $($SourceHosts -join ', ')"
    Write-Host "MinVisibleSrc:   $MinVisibleSources"
    Write-Host "Classification:  guarded multi-source DDoS-like candidate; verification must confirm source diversity" -ForegroundColor Yellow
}

if ($Scenario -eq "MixedDemo") {
    Write-Host "WARNING: MixedDemo is not clean single-label supervised training data." -ForegroundColor Yellow
}

if (-not (Test-LabHealth)) {
    exit 1
}

$startTimeUtc = (Get-Date).ToUniversalTime()

for ($round = 1; $round -le $Rounds; $round++) {
    switch ($Scenario) {
        "Benign" { Invoke-BenignScenario -Round $round }
        "UnauthorizedAccess" { Invoke-UnauthorizedAccessScenario -Round $round }
        "SqliProbe" { Invoke-SqliProbeScenario -Round $round }
        "LightDos" { Invoke-LightDosScenario -Round $round }
        "AttackerHostLightDos" { Invoke-AttackerHostLightDosScenario -Round $round }
        "MultiSourceLightDos" { Invoke-MultiSourceLightDosScenario -Round $round }
        "MixedDemo" { Invoke-MixedDemoScenario -Round $round }
    }
}

$endTimeUtc = (Get-Date).ToUniversalTime()
$metadata = Write-RunMetadata -StartTimeUtc $startTimeUtc -EndTimeUtc $endTimeUtc

Write-Host "`n============================================================"
Write-Host "SUMMARY"
Write-Host "============================================================"
Write-Host "RunId:       $($metadata.run_id)"
Write-Host "Scenario:    $($metadata.scenario)"
Write-Host "Label:       $($metadata.main_label)"
Write-Host "Sublabel:    $($metadata.sublabel)"
Write-Host "Variant:     $($metadata.scenario_variant)"
Write-Host "Planned req: $($metadata.planned_request_count)"
Write-Host "Actual req:  $($metadata.actual_request_count)"
Write-Host "Started UTC: $($metadata.start_time_utc)"
Write-Host "Ended UTC:   $($metadata.end_time_utc)"
Write-Host "Metadata:    $OutputMetadataPath"
Write-Host "`nMetadata written. Use verify-log-output.ps1 after it exists, or inspect the logs listed in the README."
