<#
.SYNOPSIS
Coordinates labelled telemetry generation, cache, verification, and export for dataset batches.

.PARAMETER InterRunDelaySeconds
Waits after each completed non-final run to reduce overlap between evidence windows. Defaults to 0.
#>

[CmdletBinding()]
param(
    [ValidateSet("Benign", "UnauthorizedAccess", "SqliProbe", "LightDos", "AttackerHostLightDos", "MultiSourceLightDos", "MixedDemo")]
    [string[]]$Scenarios = @("Benign", "UnauthorizedAccess", "SqliProbe", "LightDos"),

    [ValidateRange(1, 100)]
    [int]$RunsPerScenario = 3,

    [ValidateSet("Low", "Medium", "High")]
    [string[]]$Intensities = @("Low", "Medium"),

    [ValidateSet("normal_user", "careless_user", "attacker_single_ip", "attacker_noisy", "demo_operator")]
    [string[]]$ActorProfiles = @(),

    [string]$OutputPlanName = "training-batch",

    [switch]$Randomize,

    [ValidateRange(0, 60000)]
    [int]$DelayMs = 300,

    [ValidateRange(0, 3600)]
    [int]$TimePaddingSeconds = 5,

    [ValidateRange(0, 86400)]
    [int]$InterRunDelaySeconds = 0,

    [switch]$SkipHealthCheck,

    [switch]$ForceExports,

    [switch]$DryRun
)

$ErrorActionPreference = "Continue"

$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Join-Path (Get-Location) "scripts" }
$RepoRoot = Split-Path -Path $ScriptRoot -Parent
$ExportsRoot = Join-Path $RepoRoot "exports"
$BatchesRoot = Join-Path $ExportsRoot "batches"
$VerifiedRunsRoot = Join-Path $ExportsRoot "verified-runs"

$StartScript = Join-Path $ScriptRoot "start-and-check-lab.ps1"
$GeneratorScript = Join-Path $ScriptRoot "generate-controlled-telemetry.ps1"
$CacheScript = Join-Path $ScriptRoot "cache-lab-logs.ps1"
$VerifyScript = Join-Path $ScriptRoot "verify-log-output.ps1"
$ExportScript = Join-Path $ScriptRoot "export-lab-logs.ps1"
$AuthServerName = "auth-server"
$WebServerName = "web-server"
$ActorProfilesExplicit = $PSBoundParameters.ContainsKey("ActorProfiles")

function Write-Step {
    param([string]$Message)
    Write-Host ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Message)
}

function Get-SafeName {
    param([string]$Value)
    return (($Value.Trim()) -replace '[^A-Za-z0-9._-]', '-')
}

function Get-MainLabel {
    param([string]$Scenario)

    switch ($Scenario) {
        "Benign" { "Benign" }
        "UnauthorizedAccess" { "Unauthorized_Access" }
        "SqliProbe" { "Data_Breach" }
        "LightDos" { "DoS_DDoS" }
        "AttackerHostLightDos" { "DoS_DDoS" }
        "MultiSourceLightDos" { "DoS_DDoS" }
        "MixedDemo" { "Mixed_Demo" }
        default { $null }
    }
}

function Get-ScenarioDefaultActorProfiles {
    param([string]$Scenario)

    switch ($Scenario) {
        "Benign" { return @("normal_user", "careless_user", "demo_operator") }
        "UnauthorizedAccess" { return @("attacker_single_ip", "attacker_noisy") }
        "SqliProbe" { return @("attacker_single_ip", "attacker_noisy") }
        "LightDos" { return @("attacker_single_ip", "attacker_noisy") }
        "AttackerHostLightDos" { return @("attacker_single_ip") }
        "MultiSourceLightDos" { return @("attacker_single_ip") }
        "MixedDemo" { return @("demo_operator", "attacker_noisy") }
        default { return @("demo_operator") }
    }
}

function Get-ActorProfileSummary {
    param([string[]]$ScenarioList)

    if ($ActorProfilesExplicit) {
        return @($ActorProfiles)
    }

    $profiles = New-Object System.Collections.Generic.List[string]
    foreach ($scenario in $ScenarioList) {
        foreach ($profile in (Get-ScenarioDefaultActorProfiles -Scenario $scenario)) {
            if (-not $profiles.Contains($profile)) {
                $profiles.Add($profile) | Out-Null
            }
        }
    }

    return @($profiles.ToArray())
}

function Invoke-BatchCommand {
    param(
        [string]$Name,
        [scriptblock]$Command
    )

    Write-Step $Name
    $global:LASTEXITCODE = $null
    $passed = $true
    $exitCode = $null
    $errorMessage = ""

    try {
        & $Command
        $commandSucceeded = $?
        $exitCode = $global:LASTEXITCODE

        if ($null -ne $exitCode -and $exitCode -ne 0) {
            $passed = $false
        }
        elseif (-not $commandSucceeded) {
            $passed = $false
        }
    }
    catch {
        $passed = $false
        $errorMessage = $_.Exception.Message
        $exitCode = $global:LASTEXITCODE
    }

    if ($null -eq $exitCode) {
        if ($passed) {
            $exitCode = 0
        }
        else {
            $exitCode = 1
        }
    }

    if ($passed) {
        Write-Host "[PASS] $Name" -ForegroundColor Green
    }
    else {
        $details = "exit_code=$exitCode"
        if (-not [string]::IsNullOrWhiteSpace($errorMessage)) {
            $details = "$details error=$errorMessage"
        }

        Write-Host "[FAIL] $Name $details" -ForegroundColor Red
    }

    return [PSCustomObject]@{
        Name = $Name
        ExitCode = $exitCode
        Passed = $passed
        Error = $errorMessage
    }
}

function Run-Cmd {
    param([string]$Command)

    try {
        $output = cmd.exe /c $Command 2>&1
        return ($output -join "`n")
    }
    catch {
        return $_.Exception.Message
    }
}

function Select-LabIPv4 {
    param([string[]]$Candidates)

    $ips = @($Candidates | Where-Object {
            $_ -match "^(?:\d{1,3}\.){3}\d{1,3}$" -and
            $_ -notmatch "^127\." -and
            $_ -notmatch "^169\.254\." -and
            $_ -ne "0.0.0.0" -and
            $_ -ne "10.0.2.15"
        } | Select-Object -Unique)

    if ($ips.Count -eq 0) {
        return $null
    }

    $preferred = @($ips | Where-Object { $_ -match "^192\.168\.1\." } | Select-Object -First 1)
    if ($preferred.Count -gt 0) {
        return $preferred[0]
    }

    $private192 = @($ips | Where-Object { $_ -match "^192\.168\." } | Select-Object -First 1)
    if ($private192.Count -gt 0) {
        return $private192[0]
    }

    $private = @($ips | Where-Object { $_ -match "^10\." -or $_ -match "^172\.(1[6-9]|2[0-9]|3[0-1])\." } | Select-Object -First 1)
    if ($private.Count -gt 0) {
        return $private[0]
    }

    return $ips[0]
}

function Get-MultipassIPv4 {
    param([string]$Name)

    $candidates = @()

    $jsonText = Run-Cmd "multipass info --format json $Name"
    try {
        $json = $jsonText | ConvertFrom-Json
        $instanceInfo = $json.info.PSObject.Properties[$Name].Value
        if ($instanceInfo -and $instanceInfo.ipv4) {
            $candidates += @($instanceInfo.ipv4)
        }
    }
    catch {
        # Fall back to text parsing below.
    }

    if ($candidates.Count -eq 0) {
        $infoText = Run-Cmd "multipass info $Name"
        $candidates += @(
            [regex]::Matches($infoText, "(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])") |
                ForEach-Object { $_.Value }
        )
    }

    if ($candidates.Count -eq 0) {
        $listOutput = Run-Cmd "multipass list"
        $line = ($listOutput -split "`n" | Where-Object { $_ -match "^\s*$Name\s+" } | Select-Object -First 1)
        if ($line) {
            $candidates += @(
                [regex]::Matches($line, "(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])") |
                    ForEach-Object { $_.Value }
            )
        }
    }

    return Select-LabIPv4 -Candidates $candidates
}

function New-TargetResolutionState {
    return [ordered]@{
        ran = $false
        passed = $null
        auth_server = $AuthServerName
        web_server = $WebServerName
        auth_ip = $null
        web_ip = $null
        auth_base = $null
        web_base = $null
        errors = @()
    }
}

function Resolve-BatchTargets {
    $state = New-TargetResolutionState
    $state["ran"] = $true

    Write-Host "`nResolving telemetry target IPs from Multipass..."

    $authIp = Get-MultipassIPv4 -Name $AuthServerName
    $webIp = Get-MultipassIPv4 -Name $WebServerName

    $state["auth_ip"] = $authIp
    $state["web_ip"] = $webIp

    if ([string]::IsNullOrWhiteSpace($authIp)) {
        $state["errors"] += "Could not detect Multipass IP for $AuthServerName."
    }
    else {
        $state["auth_base"] = "http://${authIp}:8000"
    }

    if ([string]::IsNullOrWhiteSpace($webIp)) {
        $state["errors"] += "Could not detect Multipass IP for $WebServerName."
    }
    else {
        $state["web_base"] = "http://$webIp"
    }

    $state["passed"] = (@($state["errors"]).Count -eq 0)
    return $state
}

function New-RunPlan {
    param(
        [string[]]$ScenarioList,
        [int]$CountPerScenario,
        [string[]]$IntensityList,
        [string[]]$ActorProfileList,
        [bool]$UseExplicitActorProfiles,
        [string]$Timestamp
    )

    $runs = New-Object System.Collections.Generic.List[object]
    $globalSequence = 1

    foreach ($scenario in $ScenarioList) {
        for ($i = 1; $i -le $CountPerScenario; $i++) {
            $intensity = $IntensityList[($i - 1) % $IntensityList.Count]
            if ($UseExplicitActorProfiles) {
                $actorProfile = $ActorProfileList[($globalSequence - 1) % $ActorProfileList.Count]
            }
            else {
                $scenarioActorProfiles = @(Get-ScenarioDefaultActorProfiles -Scenario $scenario)
                $actorProfile = $scenarioActorProfiles[($i - 1) % $scenarioActorProfiles.Count]
            }

            $scenarioSafe = (Get-SafeName -Value $scenario).ToLowerInvariant()
            $runId = "{0}-{1}-{2:000}" -f $scenarioSafe, $Timestamp, $globalSequence
            $metadataPath = Join-Path $ExportsRoot ("{0}-metadata.json" -f $runId)
            $exportPath = Join-Path $VerifiedRunsRoot $runId

            $runs.Add([PSCustomObject]@{
                sequence = $globalSequence
                scenario_sequence = $i
                run_id = $runId
                scenario = $scenario
                label = Get-MainLabel -Scenario $scenario
                intensity = $intensity
                actor_profile = $actorProfile
                metadata_path = $metadataPath
                export_path = $exportPath
                verification_status = "planned"
                export_status = "planned"
                status = "planned"
                errors = @()
            }) | Out-Null

            $globalSequence++
        }
    }

    return @($runs.ToArray())
}

function Add-RunError {
    param(
        [object]$Run,
        [string]$Message
    )

    $errors = @($Run.errors)
    $errors += $Message
    $Run.errors = $errors
}

function ConvertTo-ManifestRun {
    param([object]$Run)

    return [ordered]@{
        sequence = $Run.sequence
        scenario_sequence = $Run.scenario_sequence
        run_id = $Run.run_id
        metadata_path = $Run.metadata_path
        export_path = $Run.export_path
        scenario = $Run.scenario
        label = $Run.label
        intensity = $Run.intensity
        actor_profile = $Run.actor_profile
        verification_status = $Run.verification_status
        export_status = $Run.export_status
        status = $Run.status
        errors = @($Run.errors)
    }
}

function Write-BatchReadme {
    param(
        [string]$Path,
        [object]$Manifest
    )

    $content = @"
# Dataset Batch: $($Manifest.batch_id)

## Purpose

This batch records planned and executed labelled scenario runs for the Coding Fest 2026 XDR lab dataset factory.

## Batch Summary

- Plan name: $($Manifest.plan_name)
- Started UTC: $($Manifest.start_time_utc)
- Ended UTC: $($Manifest.end_time_utc)
- Dry run: $($Manifest.dry_run)
- Scenarios: $(@($Manifest.scenarios) -join ", ")
- Runs per scenario: $($Manifest.runs_per_scenario)
- Intensities: $(@($Manifest.intensities) -join ", ")
- Actor profiles: $(@($Manifest.actor_profiles) -join ", ")
- Randomize: $($Manifest.randomize)
- DelayMs: $($Manifest.delay_ms)
- Time padding seconds: $($Manifest.time_padding_seconds)
- Inter-run delay seconds: $($Manifest.inter_run_delay_seconds)

## Workflow

For each non-dry-run item, the batch runner generates one metadata file, caches local logs, verifies the run with local logs, and exports only verified runs into exports\verified-runs\<run_id>\.

Failed verification marks the run as failed in batch-manifest.json and the batch continues with the next planned run.
"@

    Set-Content -Path $Path -Value $content -Encoding UTF8
}

function Write-BatchManifest {
    param(
        [string]$BatchDir,
        [string]$BatchId,
        [string]$PlanName,
        [datetime]$BatchStartUtc,
        [object]$BatchEndUtc,
        [object[]]$Runs,
        [string]$Status,
        [object]$HealthCheck,
        [object]$TargetResolution
    )

    New-Item -ItemType Directory -Force -Path $BatchDir | Out-Null

    $manifest = [ordered]@{
        batch_id = $BatchId
        plan_name = $PlanName
        status = $Status
        dry_run = [bool]$DryRun
        start_time_utc = $BatchStartUtc.ToUniversalTime().ToString("o")
        end_time_utc = if ($null -ne $BatchEndUtc) { ([datetime]$BatchEndUtc).ToUniversalTime().ToString("o") } else { $null }
        scenarios = @($Scenarios)
        runs_per_scenario = $RunsPerScenario
        intensities = @($Intensities)
        actor_profiles = @($ActorProfiles)
        randomize = [bool]$Randomize
        delay_ms = $DelayMs
        time_padding_seconds = $TimePaddingSeconds
        inter_run_delay_seconds = $InterRunDelaySeconds
        skip_health_check = [bool]$SkipHealthCheck
        force_exports = [bool]$ForceExports
        health_check = $HealthCheck
        target_resolution = $TargetResolution
        runs = @($Runs | ForEach-Object { ConvertTo-ManifestRun -Run $_ })
    }

    $manifestPath = Join-Path $BatchDir "batch-manifest.json"
    $readmePath = Join-Path $BatchDir "README.md"

    $manifest | ConvertTo-Json -Depth 10 | Set-Content -Path $manifestPath -Encoding UTF8
    Write-BatchReadme -Path $readmePath -Manifest ([PSCustomObject]$manifest)

    return [PSCustomObject]@{
        Manifest = $manifest
        ManifestPath = $manifestPath
        ReadmePath = $readmePath
    }
}

foreach ($script in @($StartScript, $GeneratorScript, $CacheScript, $VerifyScript, $ExportScript)) {
    if (-not (Test-Path -Path $script)) {
        Write-Host "Required script not found: $script" -ForegroundColor Red
        exit 1
    }
}

$batchTimestamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$safePlanName = Get-SafeName -Value $OutputPlanName
$batchId = "{0}-{1}" -f $safePlanName, $batchTimestamp
$batchDir = Join-Path $BatchesRoot $batchId
$batchStartUtc = (Get-Date).ToUniversalTime()
$ActorProfiles = @(Get-ActorProfileSummary -ScenarioList $Scenarios)
$actorProfileMode = if ($ActorProfilesExplicit) { "explicit" } else { "scenario-default" }
$runs = @(New-RunPlan -ScenarioList $Scenarios -CountPerScenario $RunsPerScenario -IntensityList $Intensities -ActorProfileList $ActorProfiles -UseExplicitActorProfiles $ActorProfilesExplicit -Timestamp $batchTimestamp)

Write-Host "============================================================"
Write-Host "Coding Fest 2026 XDR Dataset Batch Runner"
Write-Host "============================================================"
Write-Host "BatchId:            $batchId"
Write-Host "Plan:               $OutputPlanName"
Write-Host "DryRun:             $([bool]$DryRun)"
Write-Host "Scenarios:          $($Scenarios -join ', ')"
Write-Host "RunsPerScenario:    $RunsPerScenario"
Write-Host "Intensities:        $($Intensities -join ', ')"
Write-Host "ActorProfiles:      $($ActorProfiles -join ', ')"
Write-Host "ActorProfileMode:   $actorProfileMode"
Write-Host "Randomize:          $([bool]$Randomize)"
Write-Host "DelayMs:            $DelayMs"
Write-Host "TimePaddingSeconds: $TimePaddingSeconds"
Write-Host "InterRunDelaySeconds: $InterRunDelaySeconds"
Write-Host "SkipHealthCheck:    $([bool]$SkipHealthCheck)"
Write-Host "ForceExports:       $([bool]$ForceExports)"
Write-Host "Planned runs:       $($runs.Count)"

Write-Host "`nPlanned run list:"
$runs |
    Select-Object sequence, run_id, scenario, label, intensity, actor_profile, metadata_path, export_path |
    Format-Table -AutoSize -Wrap

$healthCheck = [ordered]@{
    skipped = [bool]$SkipHealthCheck
    ran = $false
    passed = $null
    exit_code = $null
}
$targetResolution = New-TargetResolutionState

if ($DryRun) {
    $batchEndUtc = (Get-Date).ToUniversalTime()
    $written = Write-BatchManifest -BatchDir $batchDir -BatchId $batchId -PlanName $OutputPlanName -BatchStartUtc $batchStartUtc -BatchEndUtc $batchEndUtc -Runs $runs -Status "dry_run" -HealthCheck $healthCheck -TargetResolution $targetResolution

    Write-Host "`nDry run only. No health check, target resolution, telemetry generation, caching, verification, or export was performed." -ForegroundColor Yellow
    Write-Host "Batch manifest: $($written.ManifestPath)"
    Write-Host "Batch README:   $($written.ReadmePath)"
    exit 0
}

if (-not $SkipHealthCheck) {
    $healthParams = @{
        SkipLinkedEvidenceTest = $true
    }

    $healthResult = Invoke-BatchCommand -Name "Health check" -Command {
        & $StartScript @healthParams
    }

    $healthCheck["ran"] = $true
    $healthCheck["passed"] = $healthResult.Passed
    $healthCheck["exit_code"] = $healthResult.ExitCode

    if (-not $healthResult.Passed) {
        foreach ($run in $runs) {
            $run.status = "skipped"
            Add-RunError -Run $run -Message "Batch health check failed before run execution."
        }

        $batchEndUtc = (Get-Date).ToUniversalTime()
        $written = Write-BatchManifest -BatchDir $batchDir -BatchId $batchId -PlanName $OutputPlanName -BatchStartUtc $batchStartUtc -BatchEndUtc $batchEndUtc -Runs $runs -Status "health_check_failed" -HealthCheck $healthCheck -TargetResolution $targetResolution
        Write-Host "Health check failed. Batch stopped before generating telemetry." -ForegroundColor Red
        Write-Host "Batch manifest: $($written.ManifestPath)"
        exit 1
    }
}

$targetResolution = Resolve-BatchTargets

Write-Host "`nResolved telemetry targets:"
Write-Host "auth-server IP: $($targetResolution["auth_ip"])"
Write-Host "web-server IP:  $($targetResolution["web_ip"])"
Write-Host "AuthBase:       $($targetResolution["auth_base"])"
Write-Host "WebBase:        $($targetResolution["web_base"])"

if (-not $targetResolution["passed"]) {
    foreach ($run in $runs) {
        $run.status = "skipped"
        foreach ($errorText in @($targetResolution["errors"])) {
            Add-RunError -Run $run -Message "Batch target resolution failed before run execution: $errorText"
        }
    }

    $batchEndUtc = (Get-Date).ToUniversalTime()
    $written = Write-BatchManifest -BatchDir $batchDir -BatchId $batchId -PlanName $OutputPlanName -BatchStartUtc $batchStartUtc -BatchEndUtc $batchEndUtc -Runs $runs -Status "target_resolution_failed" -HealthCheck $healthCheck -TargetResolution $targetResolution
    Write-Host "Target resolution failed. Batch stopped before generating telemetry." -ForegroundColor Red
    Write-Host "Batch manifest: $($written.ManifestPath)"
    exit 1
}

$ResolvedAuthBase = [string]$targetResolution["auth_base"]
$ResolvedWebBase = [string]$targetResolution["web_base"]

foreach ($run in $runs) {
    Write-Host "`n============================================================"
    Write-Host "Run $($run.sequence)/$($runs.Count): $($run.run_id)"
    Write-Host "============================================================"

    $run.status = "running"
    $run.verification_status = "not_run"
    $run.export_status = "not_run"

    $generatorParams = @{
        Scenario = $run.scenario
        Rounds = 1
        Intensity = $run.intensity
        ActorProfile = $run.actor_profile
        RunId = $run.run_id
        OutputMetadataPath = $run.metadata_path
        DelayMs = $DelayMs
        AuthBase = $ResolvedAuthBase
        WebBase = $ResolvedWebBase
    }
    if ($Randomize) {
        $generatorParams["Randomize"] = $true
    }

    $generateResult = Invoke-BatchCommand -Name "Generate telemetry $($run.run_id)" -Command {
        & $GeneratorScript @generatorParams
    }
    if (-not $generateResult.Passed) {
        $run.status = "failed"
        $message = "Telemetry generation failed with exit code $($generateResult.ExitCode)."
        if (-not [string]::IsNullOrWhiteSpace($generateResult.Error)) {
            $message = "$message Error: $($generateResult.Error)"
        }

        Add-RunError -Run $run -Message $message
        continue
    }

    if (-not (Test-Path -Path $run.metadata_path)) {
        $run.status = "failed"
        Add-RunError -Run $run -Message "Metadata file was not created: $($run.metadata_path)"
        continue
    }

    try {
        $metadata = Get-Content -Raw -Path $run.metadata_path | ConvertFrom-Json -ErrorAction Stop
        if ($metadata.main_label) {
            $run.label = [string]$metadata.main_label
        }
    }
    catch {
        Add-RunError -Run $run -Message "Metadata parse failed after generation: $($_.Exception.Message)"
    }

    $cacheParams = @{}
    $cacheResult = Invoke-BatchCommand -Name "Cache logs $($run.run_id)" -Command {
        & $CacheScript @cacheParams
    }
    if (-not $cacheResult.Passed) {
        $run.status = "failed"
        $message = "Log cache failed with exit code $($cacheResult.ExitCode)."
        if (-not [string]::IsNullOrWhiteSpace($cacheResult.Error)) {
            $message = "$message Error: $($cacheResult.Error)"
        }

        Add-RunError -Run $run -Message $message
        continue
    }

    $verifyParams = @{
        MetadataPath = $run.metadata_path
        UseLocalLogs = $true
        TimePaddingSeconds = $TimePaddingSeconds
        Strict = $true
    }
    $verifyResult = Invoke-BatchCommand -Name "Verify $($run.run_id)" -Command {
        & $VerifyScript @verifyParams
    }
    if (-not $verifyResult.Passed) {
        $run.status = "failed"
        $run.verification_status = "failed"
        $message = "Verification failed with exit code $($verifyResult.ExitCode)."
        if (-not [string]::IsNullOrWhiteSpace($verifyResult.Error)) {
            $message = "$message Error: $($verifyResult.Error)"
        }

        Add-RunError -Run $run -Message $message
        continue
    }

    $run.verification_status = "passed"

    $exportParams = @{
        MetadataPath = $run.metadata_path
        RunVerification = $true
        TimePaddingSeconds = $TimePaddingSeconds
    }
    if ($ForceExports) {
        $exportParams["Force"] = $true
    }

    $exportResult = Invoke-BatchCommand -Name "Export $($run.run_id)" -Command {
        & $ExportScript @exportParams
    }
    if (-not $exportResult.Passed) {
        $run.status = "failed"
        $run.export_status = "failed"
        $message = "Export failed with exit code $($exportResult.ExitCode)."
        if (-not [string]::IsNullOrWhiteSpace($exportResult.Error)) {
            $message = "$message Error: $($exportResult.Error)"
        }

        Add-RunError -Run $run -Message $message
        continue
    }

    $run.export_status = "exported"
    $run.status = "completed"

    if ($InterRunDelaySeconds -gt 0 -and $run.sequence -lt $runs.Count) {
        Write-Host "`nWaiting $InterRunDelaySeconds second(s) before next run to reduce evidence-window overlap..." -ForegroundColor Cyan
        Start-Sleep -Seconds $InterRunDelaySeconds
    }
}

$batchEndUtcFinal = (Get-Date).ToUniversalTime()
$completed = @($runs | Where-Object { $_.status -eq "completed" }).Count
$failed = @($runs | Where-Object { $_.status -eq "failed" }).Count
$batchStatus = if ($failed -eq 0) { "completed" } elseif ($completed -gt 0) { "completed_with_failures" } else { "failed" }
$writtenFinal = Write-BatchManifest -BatchDir $batchDir -BatchId $batchId -PlanName $OutputPlanName -BatchStartUtc $batchStartUtc -BatchEndUtc $batchEndUtcFinal -Runs $runs -Status $batchStatus -HealthCheck $healthCheck -TargetResolution $targetResolution

Write-Host "`n============================================================"
Write-Host "BATCH SUMMARY"
Write-Host "============================================================"
Write-Host "BatchId:      $batchId"
Write-Host "Status:       $batchStatus"
Write-Host "Completed:    $completed"
Write-Host "Failed:       $failed"
Write-Host "Manifest:     $($writtenFinal.ManifestPath)"
Write-Host "README:       $($writtenFinal.ReadmePath)"

if ($failed -gt 0) {
    exit 1
}

exit 0
