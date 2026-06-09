# export-wazuh-evidence-for-batch.ps1
# Adds Wazuh archive and alert evidence to completed, verified runs in a batch.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BatchManifestPath,

    [ValidateRange(0, 3600)]
    [int]$TimePaddingSeconds = 5,

    [string]$WazuhInstance = "wazuh-server"
)

$ErrorActionPreference = "Continue"

$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Join-Path (Get-Location) "scripts" }
$RepoRoot = Split-Path -Path $ScriptRoot -Parent
$ExporterPath = Join-Path $ScriptRoot "export-wazuh-evidence.ps1"
$DefaultOutputRoot = Join-Path $RepoRoot "exports\verified-runs"

function Write-Step {
    param([string]$Message)
    Write-Host ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Message)
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

Write-Host "============================================================"
Write-Host "Coding Fest 2026 XDR Batch Wazuh Evidence Export"
Write-Host "============================================================"
Write-Host "BatchManifestPath:  $BatchManifestPath"
Write-Host "TimePaddingSeconds: $TimePaddingSeconds"
Write-Host "WazuhInstance:      $WazuhInstance"

if (-not (Test-Path -Path $BatchManifestPath)) {
    Write-Host "Batch manifest not found: $BatchManifestPath" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path -Path $ExporterPath)) {
    Write-Host "Wazuh evidence exporter not found: $ExporterPath" -ForegroundColor Red
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

$eligibleRuns = @($batch.runs | Where-Object {
    ([string]$_.status -eq "completed") -and
    ([string]$_.verification_status -eq "passed")
})

if ($eligibleRuns.Count -eq 0) {
    Write-Host "No completed, verification-passed runs were found in the batch manifest." -ForegroundColor Yellow
    exit 0
}

$results = New-Object System.Collections.Generic.List[object]

foreach ($run in $eligibleRuns) {
    $metadataPath = Resolve-MetadataPath -Run $run
    $runId = [string]$run.run_id

    Write-Host "`n============================================================"
    Write-Step "Exporting Wazuh evidence for $runId"

    if ([string]::IsNullOrWhiteSpace($metadataPath) -or -not (Test-Path -Path $metadataPath)) {
        Write-Host "[FAIL] Metadata file not found for run: $runId" -ForegroundColor Red
        $results.Add([PSCustomObject]@{
            RunId = $runId
            Status = "FAIL"
            ArchiveEvents = $null
            AlertEvents = $null
            Details = "metadata not found"
        }) | Out-Null
        continue
    }

    $output = @(& powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $ExporterPath `
        -MetadataPath $metadataPath `
        -OutputRoot $DefaultOutputRoot `
        -TimePaddingSeconds $TimePaddingSeconds `
        -WazuhInstance $WazuhInstance 2>&1)
    $exitCode = $LASTEXITCODE

    foreach ($line in $output) {
        Write-Host $line
    }

    $summaryPath = Join-Path (Join-Path $DefaultOutputRoot ($runId -replace '[^A-Za-z0-9._-]', '_')) "wazuh-evidence-summary.json"
    $archiveCount = $null
    $alertCount = $null

    if ($exitCode -eq 0 -and (Test-Path -Path $summaryPath)) {
        try {
            $summary = Get-Content -Raw -Path $summaryPath | ConvertFrom-Json -ErrorAction Stop
            $archiveCount = $summary.archive_event_count
            $alertCount = $summary.alert_event_count
        }
        catch {
            Write-Host "[WARN] Export succeeded, but summary could not be parsed: $summaryPath" -ForegroundColor Yellow
        }
    }

    $results.Add([PSCustomObject]@{
        RunId = $runId
        Status = if ($exitCode -eq 0) { "PASS" } else { "FAIL" }
        ArchiveEvents = $archiveCount
        AlertEvents = $alertCount
        Details = if ($exitCode -eq 0) { $summaryPath } else { "exporter exit code $exitCode" }
    }) | Out-Null
}

$failed = @($results | Where-Object { $_.Status -eq "FAIL" }).Count

Write-Host "`n============================================================"
Write-Host "BATCH SUMMARY"
Write-Host "============================================================"
$results | Format-Table -AutoSize -Wrap
Write-Host "Eligible runs: $($eligibleRuns.Count)"
Write-Host "Passed:        $(@($results | Where-Object { $_.Status -eq 'PASS' }).Count)"
Write-Host "Failed:        $failed"

if ($failed -gt 0) {
    exit 1
}

Write-Host "Batch Wazuh evidence export completed." -ForegroundColor Green
exit 0
