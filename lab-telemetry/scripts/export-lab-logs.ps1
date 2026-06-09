# export-lab-logs.ps1
# Exports a verified labelled run into a clean raw evidence package.
# Uses local cached logs only; it does not call Multipass.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$MetadataPath,

    [string]$OutputRoot = "exports\verified-runs",

    [ValidateRange(0, 3600)]
    [int]$TimePaddingSeconds = 5,

    [switch]$RunVerification,

    [switch]$Force
)

$ErrorActionPreference = "Continue"

$LocalAuthLogPath = "exports\log-cache\auth.log"
$LocalWebLogPath = "exports\log-cache\webapp.log"
$LocalNginxLogPath = "exports\log-cache\nginx-access.log"

$VmAuthLogPath = "/home/ubuntu/auth-lab/logs/auth.log"
$VmWebLogPath = "/home/ubuntu/web-lab/logs/webapp.log"
$VmNginxAccessLogPath = "/var/log/nginx/access.log"

function Write-Step {
    param([string]$Message)
    Write-Host ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Message)
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

function Get-JsonLineTimestampUtc {
    param([string]$Line)

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return $null
    }

    try {
        $event = $Line | ConvertFrom-Json -ErrorAction Stop
        foreach ($field in @("timestamp", "@timestamp", "time", "created_at", "event_time")) {
            $property = $event.PSObject.Properties[$field]
            if ($property -and $property.Value) {
                $parsed = Convert-ToUtcDateTimeOffset -Value ([string]$property.Value)
                if ($parsed) {
                    return $parsed
                }
            }
        }
    }
    catch {
        return $null
    }

    return $null
}

function Get-NginxLineTimestampUtc {
    param([string]$Line)

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return $null
    }

    $match = [regex]::Match($Line, '\[(?<timestamp>[^\]]+)\]')
    if (-not $match.Success) {
        return $null
    }

    $timestampText = $match.Groups["timestamp"].Value
    if ($timestampText -match "^(?<prefix>\d{1,2}/[A-Za-z]{3}/\d{4}:\d{2}:\d{2}:\d{2})\s+(?<sign>[+-])(?<hours>\d{2})(?<minutes>\d{2})$") {
        $timestampText = "{0} {1}{2}:{3}" -f $matches["prefix"], $matches["sign"], $matches["hours"], $matches["minutes"]
    }

    $parsed = [DateTimeOffset]::MinValue
    foreach ($format in @("dd/MMM/yyyy:HH:mm:ss zzz", "d/MMM/yyyy:HH:mm:ss zzz")) {
        if ([DateTimeOffset]::TryParseExact($timestampText, $format, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
            return $parsed.ToUniversalTime()
        }
    }

    return $null
}

function Read-RequiredLines {
    param(
        [string]$Name,
        [string]$Path
    )

    if (-not (Test-Path -Path $Path)) {
        throw "Required local cached $Name not found: $Path. Run .\scripts\cache-lab-logs.ps1 first."
    }

    return @(Get-Content -Path $Path -ErrorAction Stop)
}

function Select-LogWindow {
    param(
        [string[]]$Lines,
        [DateTimeOffset]$WindowStartUtc,
        [DateTimeOffset]$WindowEndUtc,
        [ValidateSet("Json", "Nginx")]
        [string]$Format
    )

    $selected = New-Object System.Collections.Generic.List[string]

    foreach ($line in $Lines) {
        if ($Format -eq "Json") {
            $timestamp = Get-JsonLineTimestampUtc -Line $line
        }
        else {
            $timestamp = Get-NginxLineTimestampUtc -Line $line
        }

        if ($timestamp -and $timestamp -ge $WindowStartUtc -and $timestamp -le $WindowEndUtc) {
            $selected.Add($line) | Out-Null
        }
    }

    return @($selected)
}

function Get-MetadataValue {
    param(
        [object]$Metadata,
        [string]$Name,
        [object]$Default = $null
    )

    $property = $Metadata.PSObject.Properties[$Name]
    if ($property) {
        return $property.Value
    }

    return $Default
}

function Get-CleanTrainingCandidate {
    param([object]$Metadata)

    $cleanValue = Get-MetadataValue -Metadata $Metadata -Name "clean_supervised_training_candidate" -Default $null
    if ($null -ne $cleanValue) {
        return [bool]$cleanValue
    }

    $suitableValue = Get-MetadataValue -Metadata $Metadata -Name "suitable_for_clean_supervised_training" -Default $null
    if ($null -ne $suitableValue) {
        return [bool]$suitableValue
    }

    return ([string](Get-MetadataValue -Metadata $Metadata -Name "scenario" -Default "") -ne "MixedDemo")
}

function Invoke-OptionalVerification {
    param([string]$Path)

    $verifierPath = Join-Path $PSScriptRoot "verify-log-output.ps1"
    if (-not (Test-Path -Path $verifierPath)) {
        throw "Verifier not found: $verifierPath"
    }

    Write-Step "Running verification with local cached logs"
    $verificationOutput = & powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $verifierPath `
        -MetadataPath $Path `
        -UseLocalLogs `
        -Strict 2>&1
    $exitCode = $LASTEXITCODE

    foreach ($line in $verificationOutput) {
        Write-Host $line
    }

    $outputText = ($verificationOutput | ForEach-Object { [string]$_ }) -join "`n"
    $passed = ($exitCode -eq 0 -and $outputText -match "Verdict:\s+PASS")

    if (-not $passed) {
        throw "Verification failed or did not report Verdict: PASS. Export stopped."
    }

    return [PSCustomObject]@{
        Ran = $true
        Passed = $true
        ExitCode = $exitCode
        Output = $outputText
    }
}

function Convert-ToJsonFile {
    param(
        [object]$Value,
        [string]$Path,
        [int]$Depth = 12
    )

    $Value | ConvertTo-Json -Depth $Depth | Set-Content -Path $Path -Encoding UTF8
}

function Write-RunReadme {
    param(
        [object]$Metadata,
        [object]$Manifest,
        [string]$Path
    )

    $cleanText = if ($Manifest.clean_supervised_training_candidate) { "Yes" } else { "No" }
    $evidenceFiles = @(
        "- auth-slice.log - Auth Server JSON log lines in the run window.",
        "- webapp-slice.log - Web app JSON log lines in the run window.",
        "- nginx-access-slice.log - nginx access log lines in the run window.",
        "- metadata.json - Original run metadata copied unchanged.",
        "- manifest.json - Export manifest with labels, paths, counts, and verification status."
    ) -join "`r`n"

    $features = @($Manifest.expected_ml_features) -join ", "
    if ([string]::IsNullOrWhiteSpace($features)) {
        $features = "not specified"
    }

    $runId = [string]$Manifest.run_id
    $scenario = [string]$Manifest.scenario
    $mainLabel = [string]$Manifest.main_label
    $sublabel = [string]$Manifest.sublabel
    $actorProfile = [string]$Manifest.actor_profile
    $intensity = [string]$Manifest.intensity
    $startUtc = [string]$Manifest.start_time_utc
    $endUtc = [string]$Manifest.end_time_utc
    $padding = [string]$Manifest.time_padding_seconds

    $content = @"
# Verified XDR Lab Run: $runId

## Run Summary

This package contains a time-windowed raw evidence export for one Coding Fest 2026 XDR lab scenario run.

- Scenario: $scenario
- Main label: $mainLabel
- Sublabel: $sublabel
- Actor profile: $actorProfile
- Intensity: $intensity
- Start UTC: $startUtc
- End UTC: $endUtc
- Time padding seconds: $padding

## Included Evidence Files

$evidenceFiles

## Training Suitability

Suitable for clean supervised training: **$cleanText**.

Expected ML feature families: $features.

Use MixedDemo exports for dashboard, Wazuh collection, and correlation demonstrations rather than clean single-label supervised training data.

## Dataset Use

These slices preserve source raw evidence for later Wazuh-linked dataset construction, normalization, feature extraction, time-window aggregation, and ML preprocessing. The run_id, scenario label, sublabel, actor profile, and timestamp window should be carried forward into normalized events and model-ready rows.
"@

    Set-Content -Path $Path -Value $content -Encoding UTF8
}

Write-Host "============================================================"
Write-Host "Coding Fest 2026 XDR Verified Run Export"
Write-Host "============================================================"
Write-Host "Metadata:           $MetadataPath"
Write-Host "OutputRoot:         $OutputRoot"
Write-Host "TimePaddingSeconds: $TimePaddingSeconds"
Write-Host "RunVerification:    $([bool]$RunVerification)"

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

$runId = [string](Get-MetadataValue -Metadata $metadata -Name "run_id" -Default "")
if ([string]::IsNullOrWhiteSpace($runId)) {
    Write-Host "Metadata is missing run_id." -ForegroundColor Red
    exit 1
}

$safeRunId = ($runId -replace '[^A-Za-z0-9._-]', '_')
if ($safeRunId -ne $runId) {
    Write-Host "RunId contains path-unsafe characters. Export folder will use: $safeRunId" -ForegroundColor Yellow
}

$startTimeUtc = Convert-ToUtcDateTimeOffset -Value ([string](Get-MetadataValue -Metadata $metadata -Name "start_time_utc" -Default ""))
$endTimeUtc = Convert-ToUtcDateTimeOffset -Value ([string](Get-MetadataValue -Metadata $metadata -Name "end_time_utc" -Default ""))

if (-not $startTimeUtc -or -not $endTimeUtc) {
    Write-Host "Metadata is missing parseable start_time_utc or end_time_utc." -ForegroundColor Red
    exit 1
}

$windowStartUtc = $startTimeUtc.AddSeconds(-1 * $TimePaddingSeconds)
$windowEndUtc = $endTimeUtc.AddSeconds($TimePaddingSeconds)

$verificationResult = [PSCustomObject]@{
    Ran = $false
    Passed = $null
    ExitCode = $null
}

try {
    if ($RunVerification) {
        $verificationResult = Invoke-OptionalVerification -Path $MetadataPath
    }

    Write-Step "Reading local cached logs"
    $authLines = Read-RequiredLines -Name "auth log" -Path $LocalAuthLogPath
    $webLines = Read-RequiredLines -Name "webapp log" -Path $LocalWebLogPath
    $nginxLines = Read-RequiredLines -Name "nginx access log" -Path $LocalNginxLogPath

    Write-Step "Filtering logs to metadata time window"
    $authSlice = Select-LogWindow -Lines $authLines -WindowStartUtc $windowStartUtc -WindowEndUtc $windowEndUtc -Format Json
    $webSlice = Select-LogWindow -Lines $webLines -WindowStartUtc $windowStartUtc -WindowEndUtc $windowEndUtc -Format Json
    $nginxSlice = Select-LogWindow -Lines $nginxLines -WindowStartUtc $windowStartUtc -WindowEndUtc $windowEndUtc -Format Nginx

    New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
    $outputDir = Join-Path $OutputRoot $safeRunId

    if (Test-Path -Path $outputDir) {
        if (-not $Force) {
            throw "Output folder already exists: $outputDir. Use -Force to replace it."
        }

        Write-Host "Output folder already exists; -Force will overwrite the standard export files: $outputDir" -ForegroundColor Yellow
    }

    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

    $metadataOut = Join-Path $outputDir "metadata.json"
    $manifestOut = Join-Path $outputDir "manifest.json"
    $readmeOut = Join-Path $outputDir "README.md"
    $authOut = Join-Path $outputDir "auth-slice.log"
    $webOut = Join-Path $outputDir "webapp-slice.log"
    $nginxOut = Join-Path $outputDir "nginx-access-slice.log"

    Write-Step "Writing export package"
    Copy-Item -Path $MetadataPath -Destination $metadataOut -Force
    Set-Content -Path $authOut -Value $authSlice -Encoding UTF8
    Set-Content -Path $webOut -Value $webSlice -Encoding UTF8
    Set-Content -Path $nginxOut -Value $nginxSlice -Encoding UTF8

    $manifest = [ordered]@{
        run_id = $runId
        scenario = Get-MetadataValue -Metadata $metadata -Name "scenario" -Default $null
        main_label = Get-MetadataValue -Metadata $metadata -Name "main_label" -Default $null
        sublabel = Get-MetadataValue -Metadata $metadata -Name "sublabel" -Default $null
        scenario_variant = Get-MetadataValue -Metadata $metadata -Name "scenario_variant" -Default $null
        actor_profile = Get-MetadataValue -Metadata $metadata -Name "actor_profile" -Default $null
        intensity = Get-MetadataValue -Metadata $metadata -Name "intensity" -Default $null
        benign_activity_level = Get-MetadataValue -Metadata $metadata -Name "benign_activity_level" -Default $null
        generator_version = Get-MetadataValue -Metadata $metadata -Name "generator_version" -Default $null
        planned_request_count = Get-MetadataValue -Metadata $metadata -Name "planned_request_count" -Default $null
        actual_request_count = Get-MetadataValue -Metadata $metadata -Name "actual_request_count" -Default $null
        safety_limit_applied = Get-MetadataValue -Metadata $metadata -Name "safety_limit_applied" -Default $null
        safety_limit_reasons = @(Get-MetadataValue -Metadata $metadata -Name "safety_limit_reasons" -Default @())
        target_endpoint_family = Get-MetadataValue -Metadata $metadata -Name "target_endpoint_family" -Default $null
        attacker_host_type = Get-MetadataValue -Metadata $metadata -Name "attacker_host_type" -Default $null
        attacker_source_ip = Get-MetadataValue -Metadata $metadata -Name "attacker_source_ip" -Default $null
        target_web_base = Get-MetadataValue -Metadata $metadata -Name "target_web_base" -Default $null
        traffic_tool = Get-MetadataValue -Metadata $metadata -Name "traffic_tool" -Default $null
        attack_mode = Get-MetadataValue -Metadata $metadata -Name "attack_mode" -Default $null
        distributed = Get-MetadataValue -Metadata $metadata -Name "distributed" -Default $null
        source_count = Get-MetadataValue -Metadata $metadata -Name "source_count" -Default $null
        expected_source_count = Get-MetadataValue -Metadata $metadata -Name "expected_source_count" -Default $null
        expected_distributed = Get-MetadataValue -Metadata $metadata -Name "expected_distributed" -Default $null
        request_cap = Get-MetadataValue -Metadata $metadata -Name "request_cap" -Default $null
        concurrency = Get-MetadataValue -Metadata $metadata -Name "concurrency" -Default $null
        duration_cap_seconds = Get-MetadataValue -Metadata $metadata -Name "duration_cap_seconds" -Default $null
        target_paths = @(Get-MetadataValue -Metadata $metadata -Name "target_paths" -Default @())
        source_ip_detection_method = Get-MetadataValue -Metadata $metadata -Name "source_ip_detection_method" -Default $null
        start_time_utc = Get-MetadataValue -Metadata $metadata -Name "start_time_utc" -Default $null
        end_time_utc = Get-MetadataValue -Metadata $metadata -Name "end_time_utc" -Default $null
        export_window_start_utc = $windowStartUtc.ToString("o")
        export_window_end_utc = $windowEndUtc.ToString("o")
        time_padding_seconds = $TimePaddingSeconds
        source_log_paths = [ordered]@{
            auth = [ordered]@{
                local_cache = $LocalAuthLogPath
                vm_source = $VmAuthLogPath
            }
            webapp = [ordered]@{
                local_cache = $LocalWebLogPath
                vm_source = $VmWebLogPath
            }
            nginx_access = [ordered]@{
                local_cache = $LocalNginxLogPath
                vm_source = $VmNginxAccessLogPath
            }
        }
        output_file_paths = [ordered]@{
            output_dir = $outputDir
            metadata = $metadataOut
            manifest = $manifestOut
            readme = $readmeOut
            auth_slice = $authOut
            webapp_slice = $webOut
            nginx_access_slice = $nginxOut
        }
        line_counts_per_source = [ordered]@{
            auth = $authSlice.Count
            webapp = $webSlice.Count
            nginx_access = $nginxSlice.Count
        }
        expected_log_sources = @(Get-MetadataValue -Metadata $metadata -Name "expected_log_sources" -Default @())
        expected_ml_features = @(Get-MetadataValue -Metadata $metadata -Name "expected_ml_features" -Default @())
        clean_supervised_training_candidate = Get-CleanTrainingCandidate -Metadata $metadata
        export_created_utc = (Get-Date).ToUniversalTime().ToString("o")
        verification_ran = [bool]$verificationResult.Ran
        verification_passed = $verificationResult.Passed
    }

    Convert-ToJsonFile -Value $manifest -Path $manifestOut
    Write-RunReadme -Metadata $metadata -Manifest ([PSCustomObject]$manifest) -Path $readmeOut
}
catch {
    Write-Host "Export failed." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

Write-Host "`n============================================================"
Write-Host "SUMMARY"
Write-Host "============================================================"
Write-Host "RunId:                 $runId"
Write-Host "OutputDir:             $outputDir"
Write-Host "Auth slice lines:      $($authSlice.Count)"
Write-Host "Webapp slice lines:    $($webSlice.Count)"
Write-Host "nginx slice lines:     $($nginxSlice.Count)"
Write-Host "Verification ran:      $([bool]$verificationResult.Ran)"
Write-Host "Verification passed:   $($verificationResult.Passed)"
Write-Host "Manifest:              $manifestOut"
Write-Host "Export completed." -ForegroundColor Green
exit 0
