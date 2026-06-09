<#
.SYNOPSIS
Creates a safe v2 dataset generation plan without running it.
#>

[CmdletBinding()]
param(
    [string]$OutputPlanName = "dataset-v2-plan",
    [int]$BenignRuns = 50,
    [int]$LightDosRuns = 40,
    [int]$AttackerHostLightDosRuns = 40,
    [int]$MultiSourceLightDosRuns = 20,
    [string[]]$Intensities = @("Low", "Medium"),
    [switch]$IncludeHigh,
    [int]$InterRunDelaySeconds = 30,
    [int]$WazuhTimePaddingSeconds = 10
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Path (Split-Path -Path $MyInvocation.MyCommand.Path -Parent) -Parent
$PlansRoot = Join-Path $RepoRoot "exports\plans"
$timestamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$safeName = ($OutputPlanName -replace '[^A-Za-z0-9._-]', '-')
$planId = "$safeName-$timestamp"
$planDir = Join-Path $PlansRoot $planId
New-Item -ItemType Directory -Force -Path $planDir | Out-Null

if ($IncludeHigh -and ($Intensities -notcontains "High")) {
    $Intensities += "High"
}

$planJsonPath = Join-Path $planDir "dataset-v2-plan.json"
$planMdPath = Join-Path $planDir "dataset-v2-plan.md"
$runScriptPath = Join-Path $planDir "run-v2-dataset.ps1"

$plan = [ordered]@{
    plan_id = $planId
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    output_plan_name = $OutputPlanName
    safety = [ordered]@{
        lab_only = $true
        packet_capture = $false
        destructive_attacks = $false
        train_models = $false
        requires_manual_approval_for_large_batch = $true
        ddos_requires_multiple_visible_source_ips = $true
    }
    target_counts = [ordered]@{
        Benign = $BenignRuns
        LightDos = $LightDosRuns
        AttackerHostLightDos = $AttackerHostLightDosRuns
        MultiSourceLightDos = $MultiSourceLightDosRuns
    }
    intensities = @($Intensities)
    inter_run_delay_seconds = $InterRunDelaySeconds
    wazuh_time_padding_seconds = $WazuhTimePaddingSeconds
    multi_source_status = "pending_explicit_source_hosts_and_victim_log_confirmation"
    stages = @(
        [ordered]@{ name = "smoke"; runs_per_scenario = 1; scenarios = @("Benign", "LightDos"); requires_manual_approval = $false },
        [ordered]@{ name = "balanced-30"; runs_per_scenario = 10; scenarios = @("Benign", "LightDos", "AttackerHostLightDos"); requires_manual_approval = $true },
        [ordered]@{ name = "larger-v2"; target_counts = [ordered]@{ Benign = $BenignRuns; LightDos = $LightDosRuns; AttackerHostLightDos = $AttackerHostLightDosRuns; MultiSourceLightDos = $MultiSourceLightDosRuns }; requires_manual_approval = $true }
    )
}

$plan | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $planJsonPath -Encoding UTF8

@"
# Dataset v2 Plan

Plan ID: $planId

This plan does not run traffic. Review it before executing any generated commands.

## Target Counts

- Benign: $BenignRuns
- LightDos: $LightDosRuns
- AttackerHostLightDos: $AttackerHostLightDosRuns
- MultiSourceLightDos: $MultiSourceLightDosRuns, pending explicit multiple visible source IP support

## Safety

- Lab-only targets.
- No packet capture.
- No destructive attacks.
- No model training.
- Do not claim DDoS unless victim logs show multiple visible source IPs.
- Large batches require manual approval.

## Stages

1. Smoke: one Benign and one LightDos run.
2. Balanced 30-ish: small manually approved balanced batch.
3. Larger v2: only after quality review.

Generated runner: run-v2-dataset.ps1
"@ | Set-Content -LiteralPath $planMdPath -Encoding UTF8

@"
param(
    [switch]`$RunSmoke,
    [switch]`$RunBalanced30,
    [switch]`$RunLarger,
    [switch]`$IncludeMultiSource,
    [string[]]`$MultiSourceHosts = @("windows", "auth-server")
)

`$ErrorActionPreference = "Stop"
Set-Location "$RepoRoot"

Write-Host "Dataset v2 staged runner for $planId"
Write-Host "This script does nothing unless a stage switch is provided."

function Invoke-PostBatchBuilds {
    param([string]`$BatchManifestPath)
    .\scripts\export-wazuh-evidence-for-batch.ps1 -BatchManifestPath `$BatchManifestPath -TimePaddingSeconds $WazuhTimePaddingSeconds
    .\scripts\build-dataset-quality-summary.ps1 -BatchManifestPath `$BatchManifestPath
    .\scripts\build-ml-feature-table.ps1 -BatchManifestPath `$BatchManifestPath
    .\scripts\build-windowed-dataset.ps1 -BatchManifestPath `$BatchManifestPath -WindowSeconds 5 -StepSeconds 5 -IncludeWazuh
    .\scripts\build-labelling-candidates.ps1 -BatchManifestPath `$BatchManifestPath
    .\scripts\build-model-ready-dataset.ps1 -BatchManifestPath `$BatchManifestPath
}

function Get-LatestBatchManifest {
    `$latestBatch = Get-ChildItem .\exports\batches | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    return Join-Path `$latestBatch.FullName "batch-manifest.json"
}

.\scripts\start-and-check-lab.ps1 -SkipLinkedEvidenceTest

if (`$RunSmoke) {
    .\scripts\run-dataset-batch.ps1 -Scenarios Benign,LightDos -RunsPerScenario 1 -Intensities Low -Randomize -InterRunDelaySeconds $InterRunDelaySeconds
    Invoke-PostBatchBuilds -BatchManifestPath (Get-LatestBatchManifest)
}

if (`$RunBalanced30) {
    Write-Host "Manual approval checkpoint: balanced batch requested." -ForegroundColor Yellow
    .\scripts\run-dataset-batch.ps1 -Scenarios Benign,LightDos,AttackerHostLightDos -RunsPerScenario 10 -Intensities $($Intensities -join ',') -Randomize -InterRunDelaySeconds $InterRunDelaySeconds
    Invoke-PostBatchBuilds -BatchManifestPath (Get-LatestBatchManifest)
}

if (`$RunLarger) {
    Write-Host "Manual approval checkpoint: larger v2 batch requested." -ForegroundColor Yellow
    .\scripts\run-dataset-batch.ps1 -Scenarios Benign -RunsPerScenario $BenignRuns -Intensities $($Intensities -join ',') -Randomize -InterRunDelaySeconds $InterRunDelaySeconds
    Invoke-PostBatchBuilds -BatchManifestPath (Get-LatestBatchManifest)
    .\scripts\run-dataset-batch.ps1 -Scenarios LightDos -RunsPerScenario $LightDosRuns -Intensities $($Intensities -join ',') -Randomize -InterRunDelaySeconds $InterRunDelaySeconds
    Invoke-PostBatchBuilds -BatchManifestPath (Get-LatestBatchManifest)
    .\scripts\run-dataset-batch.ps1 -Scenarios AttackerHostLightDos -RunsPerScenario $AttackerHostLightDosRuns -Intensities $($Intensities -join ',') -Randomize -InterRunDelaySeconds $InterRunDelaySeconds
    Invoke-PostBatchBuilds -BatchManifestPath (Get-LatestBatchManifest)
}

if (`$IncludeMultiSource) {
    Write-Host "MultiSourceLightDos is not run through run-dataset-batch by default because it requires explicit source-host confirmation." -ForegroundColor Yellow
    Write-Host "Smoke manually with generate-controlled-telemetry.ps1 -Scenario MultiSourceLightDos -SourceHosts `$MultiSourceHosts -RequireMultipleSources."
}
"@ | Set-Content -LiteralPath $runScriptPath -Encoding UTF8

Write-Host "Plan JSON: $planJsonPath"
Write-Host "Plan Markdown: $planMdPath"
Write-Host "Generated staged runner: $runScriptPath"
