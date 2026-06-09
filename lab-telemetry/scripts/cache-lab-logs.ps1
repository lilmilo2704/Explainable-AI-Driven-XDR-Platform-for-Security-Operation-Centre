# cache-lab-logs.ps1
# Caches lab logs locally using VM-side copy/tail plus multipass transfer.

[CmdletBinding()]
param(
    [ValidateRange(0, 50000)]
    [int]$TailLines = 0,

    [string]$OutputDir = "exports\log-cache",

    [switch]$SkipAuth,
    [switch]$SkipWeb,
    [switch]$SkipNginx
)

$ErrorActionPreference = "Continue"

$AuthHost = "auth-server"
$WebHost = "web-server"

$AuthLogPath = "/home/ubuntu/auth-lab/logs/auth.log"
$WebLogPath = "/home/ubuntu/web-lab/logs/webapp.log"
$NginxAccessLogPath = "/var/log/nginx/access.log"

$AuthTempPath = "/tmp/xdr-cache-auth.log"
$WebTempPath = "/tmp/xdr-cache-webapp.log"
$NginxTempPath = "/tmp/xdr-cache-nginx-access.log"

function Invoke-LoggedCommand {
    param(
        [string]$Display,
        [scriptblock]$Command
    )

    Write-Host "Command: $Display"
    & $Command
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        Write-Host "[FAIL] Command failed with exit code $exitCode" -ForegroundColor Red
        Write-Host "Failed command: $Display" -ForegroundColor Yellow
        return $false
    }

    return $true
}

function Get-LocalFileSizeText {
    param([string]$Path)

    if (-not (Test-Path -Path $Path)) {
        return "missing"
    }

    $item = Get-Item -Path $Path
    return "$($item.Length) bytes"
}

function Save-LogWithTransfer {
    param(
        [string]$Name,
        [string]$HostName,
        [string]$RemoteSourcePath,
        [string]$RemoteTempPath,
        [string]$LocalPath,
        [switch]$UseSudo
    )

    Write-Host "============================================================"
    Write-Host "Caching $Name"
    Write-Host "Remote source: $HostName`:$RemoteSourcePath"
    Write-Host "Remote temp:   $HostName`:$RemoteTempPath"
    Write-Host "Local cache:   $LocalPath"

    Write-Host "Preparing remote temp file..."
    if ($TailLines -eq 0) {
        if ($UseSudo) {
            $display = "multipass exec $HostName -- sudo cp $RemoteSourcePath $RemoteTempPath"
            $prepared = Invoke-LoggedCommand -Display $display -Command {
                & multipass exec $HostName -- sudo cp $RemoteSourcePath $RemoteTempPath
            }
        }
        else {
            $display = "multipass exec $HostName -- cp $RemoteSourcePath $RemoteTempPath"
            $prepared = Invoke-LoggedCommand -Display $display -Command {
                & multipass exec $HostName -- cp $RemoteSourcePath $RemoteTempPath
            }
        }
    }
    else {
        $tailCommand = "tail -n $TailLines $RemoteSourcePath > $RemoteTempPath"
        if ($UseSudo) {
            $display = "multipass exec $HostName -- sudo sh -c `"$tailCommand`""
            $prepared = Invoke-LoggedCommand -Display $display -Command {
                & multipass exec $HostName -- sudo sh -c $tailCommand
            }
        }
        else {
            $display = "multipass exec $HostName -- sh -c `"$tailCommand`""
            $prepared = Invoke-LoggedCommand -Display $display -Command {
                & multipass exec $HostName -- sh -c $tailCommand
            }
        }
    }

    if (-not $prepared) {
        Write-Host "[FAIL] $Name remote temp preparation failed" -ForegroundColor Red
        return [PSCustomObject]@{
            Name = $Name
            Status = "FAIL"
            LocalPath = $LocalPath
            Size = Get-LocalFileSizeText -Path $LocalPath
        }
    }

    if ($UseSudo) {
        $chmodDisplay = "multipass exec $HostName -- sudo chmod 644 $RemoteTempPath"
        $chmodOk = Invoke-LoggedCommand -Display $chmodDisplay -Command {
            & multipass exec $HostName -- sudo chmod 644 $RemoteTempPath
        }

        if (-not $chmodOk) {
            Write-Host "[FAIL] $Name remote chmod failed" -ForegroundColor Red
            return [PSCustomObject]@{
                Name = $Name
                Status = "FAIL"
                LocalPath = $LocalPath
                Size = Get-LocalFileSizeText -Path $LocalPath
            }
        }
    }

    Write-Host "Transferring to local cache..."
    Remove-Item -Path $LocalPath -Force -ErrorAction SilentlyContinue

    $remoteSpec = "${HostName}:$RemoteTempPath"
    $transferDisplay = "multipass transfer $remoteSpec $LocalPath"
    $transferred = Invoke-LoggedCommand -Display $transferDisplay -Command {
        & multipass transfer $remoteSpec $LocalPath
    }

    if (-not $transferred) {
        Write-Host "[FAIL] $Name transfer failed" -ForegroundColor Red
        return [PSCustomObject]@{
            Name = $Name
            Status = "FAIL"
            LocalPath = $LocalPath
            Size = Get-LocalFileSizeText -Path $LocalPath
        }
    }

    $size = Get-LocalFileSizeText -Path $LocalPath
    Write-Host "[PASS] $Name cached ($size)" -ForegroundColor Green

    return [PSCustomObject]@{
        Name = $Name
        Status = "PASS"
        LocalPath = $LocalPath
        Size = $size
    }
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$authLocal = Join-Path $OutputDir "auth.log"
$webLocal = Join-Path $OutputDir "webapp.log"
$nginxLocal = Join-Path $OutputDir "nginx-access.log"

Write-Host "============================================================"
Write-Host "Coding Fest 2026 XDR Lab Log Cache"
Write-Host "============================================================"
Write-Host "Mode:      $(if ($TailLines -eq 0) { 'full copy' } else { "tail $TailLines lines" })"
Write-Host "TailLines: $TailLines"
Write-Host "OutputDir: $OutputDir"

$results = @()

if (-not $SkipAuth) {
    $results += Save-LogWithTransfer `
        -Name "auth log" `
        -HostName $AuthHost `
        -RemoteSourcePath $AuthLogPath `
        -RemoteTempPath $AuthTempPath `
        -LocalPath $authLocal
}
else {
    Write-Host "Skipping auth log cache."
}

if (-not $SkipWeb) {
    $results += Save-LogWithTransfer `
        -Name "webapp log" `
        -HostName $WebHost `
        -RemoteSourcePath $WebLogPath `
        -RemoteTempPath $WebTempPath `
        -LocalPath $webLocal
}
else {
    Write-Host "Skipping webapp log cache."
}

if (-not $SkipNginx) {
    $results += Save-LogWithTransfer `
        -Name "nginx access log" `
        -HostName $WebHost `
        -RemoteSourcePath $NginxAccessLogPath `
        -RemoteTempPath $NginxTempPath `
        -LocalPath $nginxLocal `
        -UseSudo
}
else {
    Write-Host "Skipping nginx access log cache."
}

$failed = @($results | Where-Object { $_.Status -eq "FAIL" }).Count

Write-Host "`n============================================================"
Write-Host "SUMMARY"
Write-Host "============================================================"

if ($results.Count -gt 0) {
    $results | Format-Table -AutoSize
}
else {
    Write-Host "No logs were selected for caching."
}

Write-Host "Expected cache paths:"
Write-Host "Auth:  $authLocal"
Write-Host "Web:   $webLocal"
Write-Host "nginx: $nginxLocal"

if ($failed -gt 0) {
    Write-Host "One or more cache steps failed." -ForegroundColor Red
    exit 1
}

Write-Host "Log cache completed." -ForegroundColor Green
exit 0
