param(
    [switch]$SkipPythonDeps,
    [switch]$SkipNpmInstall,
    [string]$DatabaseUrl = "postgresql+psycopg2://xdr:xdrpass@localhost:5432/xdrdb",
    [string]$MlServiceUrl = "http://localhost:5000",
    [string]$ApiBaseUrl = "http://localhost:8000"
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $projectRoot "docker-compose.yml"))) {
    throw "Run this script from xdr-platform/scripts (or keep file there). Could not find docker-compose.yml at project root."
}

$backendDir = Join-Path $projectRoot "backend"
$mlDir = Join-Path $projectRoot "ml-service"
$legacyMlDir = Join-Path $projectRoot "ml-services"
$frontendDir = Join-Path $projectRoot "frontend"
$samplesDir = Join-Path $projectRoot "samples"

if (Test-Path $legacyMlDir) {
    Write-Host "Warning: Found legacy folder 'ml-services'. Active runtime folder is 'ml-service'." -ForegroundColor Yellow
}

function Ensure-PythonVenv {
    param(
        [Parameter(Mandatory = $true)][string]$ServiceDir,
        [Parameter(Mandatory = $true)][string]$RequirementsFile
    )

    $venvDir = Join-Path $ServiceDir ".venv"
    $pythonExe = Join-Path $venvDir "Scripts\python.exe"

    if (-not (Test-Path $pythonExe)) {
        Write-Host "Creating virtual environment in $ServiceDir" -ForegroundColor Cyan
        Push-Location $ServiceDir
        python -m venv .venv
        Pop-Location
    }

    if (-not $SkipPythonDeps) {
        Write-Host "Installing Python dependencies in $ServiceDir" -ForegroundColor Cyan
        & $pythonExe -m pip install --upgrade pip | Out-Null
        & $pythonExe -m pip install -r $RequirementsFile
    }
}

if (-not (Test-Path $backendDir)) { throw "Missing backend directory: $backendDir" }
if (-not (Test-Path $mlDir)) { throw "Missing ml-service directory: $mlDir" }
if (-not (Test-Path $frontendDir)) { throw "Missing frontend directory: $frontendDir" }

$backendReq = Join-Path $backendDir "requirements.txt"
$mlReq = Join-Path $mlDir "requirements.txt"

if (-not (Test-Path $backendReq)) { throw "Missing backend requirements.txt" }
if (-not (Test-Path $mlReq)) { throw "Missing ml-service requirements.txt" }

$dbProbe = Test-NetConnection localhost -Port 5432 -WarningAction SilentlyContinue
if (-not $dbProbe.TcpTestSucceeded) {
    throw "PostgreSQL is not reachable at localhost:5432. Start local DB first, then rerun."
}

Ensure-PythonVenv -ServiceDir $backendDir -RequirementsFile $backendReq
Ensure-PythonVenv -ServiceDir $mlDir -RequirementsFile $mlReq

if (-not $SkipNpmInstall) {
    Write-Host "Installing frontend dependencies" -ForegroundColor Cyan
    Push-Location $frontendDir
    npm install
    Pop-Location
}

$mlCommand = @"
Set-Location '$mlDir'
& '.\.venv\Scripts\Activate.ps1'
uvicorn main:app --host 0.0.0.0 --port 5000 --reload
"@

$backendCommand = @"
Set-Location '$backendDir'
& '.\.venv\Scripts\Activate.ps1'
`$env:DATABASE_URL='$DatabaseUrl'
`$env:ML_SERVICE_URL='$MlServiceUrl'
`$env:SEED_ALERTS_PATH='$((Join-Path $samplesDir "seed_alerts.json"))'
`$env:SEED_MULTI_STAGE_PATH='$((Join-Path $samplesDir "multi_stage_window.json"))'
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
"@

$frontendCommand = @"
Set-Location '$frontendDir'
`$env:VITE_API_BASE_URL='$ApiBaseUrl'
npm run dev
"@

Write-Host "Starting ML service window..." -ForegroundColor Green
Start-Process powershell -ArgumentList "-NoProfile", "-NoExit", "-ExecutionPolicy", "Bypass", "-Command", $mlCommand

Start-Sleep -Milliseconds 600

Write-Host "Starting backend service window..." -ForegroundColor Green
Start-Process powershell -ArgumentList "-NoProfile", "-NoExit", "-ExecutionPolicy", "Bypass", "-Command", $backendCommand

Start-Sleep -Milliseconds 600

Write-Host "Starting frontend service window..." -ForegroundColor Green
Start-Process powershell -ArgumentList "-NoProfile", "-NoExit", "-ExecutionPolicy", "Bypass", "-Command", $frontendCommand

Write-Host ""
Write-Host "All 3 app services are launching in separate windows." -ForegroundColor Green
Write-Host "Frontend: http://localhost:5173" -ForegroundColor Yellow
Write-Host "Backend : http://localhost:8000" -ForegroundColor Yellow
Write-Host "ML      : http://localhost:5000" -ForegroundColor Yellow
Write-Host ""
Write-Host "Seed demo data once backend is up:" -ForegroundColor Cyan
Write-Host "curl -X POST http://localhost:8000/api/mock/seed" -ForegroundColor White
Write-Host ""
Write-Host "Note: PostgreSQL must already be running locally on localhost:5432." -ForegroundColor Magenta
