# start-and-check-lab.ps1
# Starts and validates the Coding Fest 2026 XDR lab.
# Run from Windows PowerShell.

param(
    [string]$AuthServer = "auth-server",
    [string]$WebServer = "web-server",
    [string]$DbServer = "db-server",

    [string]$AuthBase = "",
    [string]$WebBase = "",

    [switch]$SkipLinkedEvidenceTest
)

$ErrorActionPreference = "Continue"

$Results = @()
$ResolvedTargets = [ordered]@{}
$MultipassListOutput = ""

function Add-Result {
    param(
        [string]$Name,
        [bool]$Passed,
        [string]$Details = ""
    )

    $script:Results += [PSCustomObject]@{
        Check = $Name
        Status = if ($Passed) { "PASS" } else { "FAIL" }
        Details = $Details
    }

    if ($Passed) {
        Write-Host "[PASS] $Name $Details" -ForegroundColor Green
    }
    else {
        Write-Host "[FAIL] $Name $Details" -ForegroundColor Red
    }
}

function Write-Diagnostic {
    param([string]$Message)

    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        Write-Host "[DIAG] $Message" -ForegroundColor Yellow
    }
}

function Run-Cmd {
    param(
        [string]$Command
    )

    try {
        $output = cmd.exe /c $Command 2>&1
        return ($output -join "`n")
    }
    catch {
        return $_.Exception.Message
    }
}

function Invoke-RemoteBash {
    param(
        [string]$Instance,
        [string]$Script
    )

    return Run-Cmd "multipass exec $Instance -- bash -lc `"$Script`""
}

function Show-SummaryAndExit {
    Write-Host "`n============================================================"
    Write-Host "SUMMARY"
    Write-Host "============================================================"

    $Results | Format-Table -AutoSize

    $failed = $Results | Where-Object { $_.Status -eq "FAIL" }

    if ($failed.Count -eq 0) {
        Write-Host "`nLab is healthy and ready." -ForegroundColor Green
        exit 0
    }
    else {
        Write-Host "`nLab has issues. Review FAIL rows above." -ForegroundColor Red
        exit 1
    }
}

function Test-MultipassAccess {
    $script:MultipassListOutput = Run-Cmd "multipass list"

    if ($script:MultipassListOutput -match "cannot connect to the multipass socket" -or
        $script:MultipassListOutput -match "list failed" -or
        $script:MultipassListOutput -match "certificate verify failed") {
        Add-Result "Multipass CLI reachable" $false $script:MultipassListOutput.Trim()
        Write-Diagnostic "Multipass commands are failing before VM checks can run. Start/restart Multipass or fix the local client certificate/socket issue, then rerun this script."
        return $false
    }

    Add-Result "Multipass CLI reachable" $true
    return $true
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

function Resolve-LabTarget {
    param(
        [string]$Name,
        [string]$Role
    )

    $ip = Get-MultipassIPv4 -Name $Name

    if ([string]::IsNullOrWhiteSpace($ip)) {
        Add-Result "Multipass IP detected: $Name" $false "$Role VM IP could not be detected from multipass info/list"
        return $null
    }

    Add-Result "Multipass IP detected: $Name" $true $ip
    $script:ResolvedTargets[$Name] = $ip
    return $ip
}

function Get-UriHostSafe {
    param([string]$Url)

    try {
        return ([Uri]$Url).Host
    }
    catch {
        return ""
    }
}

function Write-StaleIpDiagnostic {
    param(
        [string]$Name,
        [string]$Url,
        [string]$DetectedIp
    )

    $hostName = Get-UriHostSafe -Url $Url
    if (-not [string]::IsNullOrWhiteSpace($hostName) -and
        -not [string]::IsNullOrWhiteSpace($DetectedIp) -and
        $hostName -ne $DetectedIp) {
        Write-Diagnostic "$Name target host is $hostName, but Multipass reports $DetectedIp. This is a stale IP or manual target mismatch."
    }
}

function Ensure-MultipassInstance {
    param(
        [string]$Name
    )

    Write-Host "`nChecking Multipass instance: $Name"

    $listOutput = if ([string]::IsNullOrWhiteSpace($script:MultipassListOutput)) { Run-Cmd "multipass list" } else { $script:MultipassListOutput }
    $line = ($listOutput -split "`n" | Where-Object { $_ -match "^\s*$Name\s+" } | Select-Object -First 1)

    if (-not $line) {
        Add-Result "Multipass instance exists: $Name" $false "Instance not found"
        return $false
    }

    Add-Result "Multipass instance exists: $Name" $true

    if ($line -match "Running") {
        Add-Result "Multipass instance running: $Name" $true
        return $true
    }

    Write-Host "Starting $Name..."
    $startOutput = Run-Cmd "multipass start $Name"
    Start-Sleep -Seconds 8

    $listOutputAfter = Run-Cmd "multipass list"
    $lineAfter = ($listOutputAfter -split "`n" | Where-Object { $_ -match "^\s*$Name\s+" } | Select-Object -First 1)

    if ($lineAfter -match "Running") {
        Add-Result "Multipass instance started: $Name" $true
        return $true
    }

    Add-Result "Multipass instance started: $Name" $false $startOutput
    return $false
}

function Ensure-Service {
    param(
        [string]$Instance,
        [string]$Service
    )

    Write-Host "`nChecking service $Service on $Instance"

    $status = Run-Cmd "multipass exec $Instance -- sudo systemctl is-active $Service"
    $status = $status.Trim()

    if ($status -eq "active") {
        Start-Sleep -Seconds 2
        $stableStatus = Run-Cmd "multipass exec $Instance -- sudo systemctl is-active $Service"
        $stableStatus = $stableStatus.Trim()

        if ($stableStatus -ne "active") {
            $details = Run-Cmd "multipass exec $Instance -- sudo systemctl status $Service --no-pager"
            Add-Result "$Instance service stable: $Service" $false "Service was active, then became $stableStatus. $details"
            return $false
        }

        Add-Result "$Instance service active: $Service" $true
        return $true
    }

    Write-Host "Restarting $Service on $Instance..."
    Run-Cmd "multipass exec $Instance -- sudo systemctl restart $Service" | Out-Null
    Start-Sleep -Seconds 5

    $statusAfter = Run-Cmd "multipass exec $Instance -- sudo systemctl is-active $Service"
    $statusAfter = $statusAfter.Trim()

    if ($statusAfter -eq "active") {
        Add-Result "$Instance service restarted: $Service" $true
        return $true
    }

    $details = Run-Cmd "multipass exec $Instance -- sudo systemctl status $Service --no-pager"
    Add-Result "$Instance service restarted: $Service" $false $details
    return $false
}

function Update-AppIpConfig {
    param(
        [string]$Name,
        [string]$Instance,
        [string]$Path,
        [string]$ExpectedDbIp = "",
        [string]$ExpectedAuthIp = ""
    )

    $changed = $false
    $pathCheck = Invoke-RemoteBash -Instance $Instance -Script "if [ -f $Path ]; then echo EXISTS; else echo MISSING; fi"

    if ($pathCheck -notmatch "EXISTS") {
        Add-Result "$Name app config file exists" $false "$Path not found on $Instance"
        return $false
    }

    Add-Result "$Name app config file exists" $true $Path

    if (-not [string]::IsNullOrWhiteSpace($ExpectedDbIp)) {
        $dbCheck = Invoke-RemoteBash -Instance $Instance -Script "if grep -q '@$ExpectedDbIp`:5432' $Path; then echo CURRENT; else echo STALE; fi"

        if ($dbCheck -match "CURRENT") {
            Add-Result "$Name DB target config current" $true "uses $ExpectedDbIp"
        }
        else {
            Write-Host "Updating $Name DB target in $Path to $ExpectedDbIp..."
            $backupAndUpdate = "sudo cp $Path $Path.xdr-ip-backup-`$(date +%Y%m%d%H%M%S); sudo sed -i -E 's#@[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:5432#@$ExpectedDbIp`:5432#g' $Path"
            Invoke-RemoteBash -Instance $Instance -Script $backupAndUpdate | Out-Null

            $verifyDb = Invoke-RemoteBash -Instance $Instance -Script "if grep -q '@$ExpectedDbIp`:5432' $Path; then echo UPDATED; else echo FAILED; fi"
            if ($verifyDb -match "UPDATED") {
                Add-Result "$Name DB target config updated" $true "uses $ExpectedDbIp"
                $changed = $true
            }
            else {
                $foundOutput = Invoke-RemoteBash -Instance $Instance -Script "grep -n -E '@[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:5432' $Path || true"
                Add-Result "$Name DB target config updated" $false "Expected $ExpectedDbIp in $Path; found: $($foundOutput.Trim())"
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($ExpectedAuthIp)) {
        $authCheck = Invoke-RemoteBash -Instance $Instance -Script "if grep -q 'http://$ExpectedAuthIp`:8000' $Path; then echo CURRENT; else echo STALE; fi"

        if ($authCheck -match "CURRENT") {
            Add-Result "$Name Auth API target config current" $true "uses $ExpectedAuthIp"
        }
        else {
            Write-Host "Updating $Name Auth API target in $Path to $ExpectedAuthIp..."
            $backupAndUpdate = "sudo cp $Path $Path.xdr-ip-backup-`$(date +%Y%m%d%H%M%S); sudo sed -i -E 's#http://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:8000#http://$ExpectedAuthIp`:8000#g' $Path"
            Invoke-RemoteBash -Instance $Instance -Script $backupAndUpdate | Out-Null

            $verifyAuth = Invoke-RemoteBash -Instance $Instance -Script "if grep -q 'http://$ExpectedAuthIp`:8000' $Path; then echo UPDATED; else echo FAILED; fi"
            if ($verifyAuth -match "UPDATED") {
                Add-Result "$Name Auth API target config updated" $true "uses $ExpectedAuthIp"
                $changed = $true
            }
            else {
                $foundOutput = Invoke-RemoteBash -Instance $Instance -Script "grep -n -E 'http://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:8000' $Path || true"
                Add-Result "$Name Auth API target config updated" $false "Expected $ExpectedAuthIp in $Path; found: $($foundOutput.Trim())"
            }
        }
    }

    return $changed
}

function Write-HttpDiagnostics {
    param(
        [string]$Name,
        [string]$Instance,
        [string]$Url,
        [int]$PublicPort,
        [string]$LocalHealthUrl,
        [string]$ServiceName,
        [string]$DetectedIp,
        [switch]$CheckNginx
    )

    Write-Host "`nDiagnostics for $Name HTTP health" -ForegroundColor Yellow

    Write-StaleIpDiagnostic -Name $Name -Url $Url -DetectedIp $DetectedIp

    $serviceStatus = (Run-Cmd "multipass exec $Instance -- sudo systemctl is-active $ServiceName").Trim()
    if ($serviceStatus -eq "active") {
        Write-Diagnostic "$ServiceName is active on $Instance, so a failed endpoint can indicate binding, firewall, upstream, or app-health issues."
    }
    else {
        Write-Diagnostic "$ServiceName is not active on $Instance. Endpoint health cannot pass until the service starts."
    }

    $localHealth = Run-Cmd "multipass exec $Instance -- curl -sS --max-time 5 $LocalHealthUrl"
    if ($localHealth -match '"status"\s*:\s*"ok"') {
        Write-Diagnostic "$Instance can reach $LocalHealthUrl locally. If Windows cannot reach $Url, check stale target IP, LAN routing, or firewall/UFW."
    }
    else {
        Write-Diagnostic "$Instance local health check did not return status=ok. Service may be active but endpoint unhealthy."
        Write-Diagnostic ($localHealth.Trim())
    }

    $listenOutput = Run-Cmd "multipass exec $Instance -- ss -ltn"
    $listenLines = @($listenOutput -split "`n" | Where-Object { $_ -match ":$PublicPort\s" })
    if ($listenLines.Count -eq 0) {
        Write-Diagnostic "$Instance is not listening on TCP port $PublicPort."
    }
    else {
        Write-Diagnostic "$Instance listening sockets for port ${PublicPort}: $($listenLines -join ' | ')"
        $joinedListenLines = $listenLines -join "`n"
        $localhostOnly = $joinedListenLines -match "(127\.0\.0\.1|::1):$PublicPort"
        $allInterfaces = $joinedListenLines -match "(0\.0\.0\.0|\[::\]|\*)[: ]$PublicPort"
        if ($localhostOnly -and -not $allInterfaces) {
            Write-Diagnostic "App appears bound only to localhost on $Instance. Bind to 0.0.0.0 or expose through nginx as intended."
        }
    }

    $ufwStatus = Run-Cmd "multipass exec $Instance -- sudo ufw status"
    if ($ufwStatus -match "Status:\s+active") {
        if ($ufwStatus -notmatch "\b$PublicPort\b") {
            Write-Diagnostic "UFW is active and no explicit allow rule for port $PublicPort was found."
        }
        else {
            Write-Diagnostic "UFW is active; verify the rule for port $PublicPort allows the Windows host/LAN."
        }
    }
    else {
        Write-Diagnostic "UFW does not appear active, so firewall blocking inside the VM is less likely."
    }

    if ($CheckNginx) {
        $nginxStatus = (Run-Cmd "multipass exec $Instance -- sudo systemctl is-active nginx").Trim()
        Write-Diagnostic "nginx service status on ${Instance}: $nginxStatus"

        $upstreamHealth = Run-Cmd "multipass exec $Instance -- curl -sS --max-time 5 http://127.0.0.1:8001/health"
        if ($upstreamHealth -match '"status"\s*:\s*"ok"') {
            Write-Diagnostic "nginx upstream app on 127.0.0.1:8001 returned status=ok."
        }
        else {
            Write-Diagnostic "nginx upstream app on 127.0.0.1:8001 did not return status=ok. This points to a web-lab upstream issue."
            Write-Diagnostic ($upstreamHealth.Trim())
        }

        $nginxTest = Run-Cmd "multipass exec $Instance -- sudo nginx -t"
        if ($nginxTest -match "syntax is ok" -and $nginxTest -match "test is successful") {
            Write-Diagnostic "nginx configuration test passed."
        }
        else {
            Write-Diagnostic "nginx configuration test did not pass: $($nginxTest.Trim())"
        }

        $nginxErrors = Run-Cmd "multipass exec $Instance -- sudo tail -n 10 /var/log/nginx/error.log"
        if (-not [string]::IsNullOrWhiteSpace($nginxErrors)) {
            Write-Diagnostic "Recent nginx error log: $($nginxErrors.Trim())"
        }
    }
}

function Test-HttpHealth {
    param(
        [string]$Name,
        [string]$Url,
        [string]$Instance,
        [int]$PublicPort,
        [string]$LocalHealthUrl,
        [string]$ServiceName,
        [string]$DetectedIp,
        [switch]$CheckNginx
    )

    Write-Host "`nChecking HTTP health: $Name $Url"

    if ([string]::IsNullOrWhiteSpace($Url)) {
        Add-Result "$Name HTTP health" $false "Skipped because target URL is unavailable"
        return $false
    }

    try {
        $response = Invoke-RestMethod -Uri $Url -Method GET -TimeoutSec 10 -ErrorAction Stop
        if ($response.status -eq "ok") {
            Add-Result "$Name HTTP health" $true "service=$($response.service)"
            return $true
        }

        Add-Result "$Name HTTP health" $false "Unexpected response: $response"
        Write-HttpDiagnostics -Name $Name -Instance $Instance -Url $Url -PublicPort $PublicPort -LocalHealthUrl $LocalHealthUrl -ServiceName $ServiceName -DetectedIp $DetectedIp -CheckNginx:$CheckNginx
        return $false
    }
    catch {
        Add-Result "$Name HTTP health" $false $_.Exception.Message
        Write-HttpDiagnostics -Name $Name -Instance $Instance -Url $Url -PublicPort $PublicPort -LocalHealthUrl $LocalHealthUrl -ServiceName $ServiceName -DetectedIp $DetectedIp -CheckNginx:$CheckNginx
        return $false
    }
}

function Test-DbTables {
    Write-Host "`nChecking PostgreSQL tables"

    $query = "SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename;"
    $cmd = "multipass exec $DbServer -- sudo -u postgres psql -d xdr_lab -t -c `"$query`""
    $output = Run-Cmd $cmd

    $requiredTables = @("users", "login_attempts", "web_events")

    foreach ($table in $requiredTables) {
        if ($output -match "\b$table\b") {
            Add-Result "Database table exists: $table" $true
        }
        else {
            Add-Result "Database table exists: $table" $false "Not found in xdr_lab"
        }
    }
}

function Test-LinkedEvidence {
    Write-Host "`nTesting linked web/auth evidence"

    if ([string]::IsNullOrWhiteSpace($WebBase)) {
        Add-Result "Linked evidence test" $false "Skipped because WebBase is unavailable"
        return $false
    }

    try {
        Invoke-WebRequest `
            -Uri "$WebBase/login" `
            -Method POST `
            -Body @{ username = "admin"; password = "AdminPass123!" } `
            -UseBasicParsing `
            -TimeoutSec 10 | Out-Null

        Start-Sleep -Seconds 2

        $webLog = Run-Cmd "multipass exec $WebServer -- tail -n 10 /home/ubuntu/web-lab/logs/webapp.log"
        $authLog = Run-Cmd "multipass exec $AuthServer -- tail -n 10 /home/ubuntu/auth-lab/logs/auth.log"

        $webOk = ($webLog -match "web_login_attempt") -and ($webLog -match "login_success")
        $authOk = ($authLog -match "login_success") -and ($authLog -match "valid_credentials")

        Add-Result "Linked evidence: web login event" $webOk
        Add-Result "Linked evidence: auth login event" $authOk

        return ($webOk -and $authOk)
    }
    catch {
        Add-Result "Linked evidence test" $false $_.Exception.Message
        return $false
    }
}

Write-Host "============================================================"
Write-Host "Coding Fest 2026 XDR Lab Start + Health Check"
Write-Host "============================================================"

if (-not (Test-MultipassAccess)) {
    Show-SummaryAndExit
}

Write-Host "`nStep 1: Checking Multipass instances"
Ensure-MultipassInstance $DbServer | Out-Null
Ensure-MultipassInstance $AuthServer | Out-Null
Ensure-MultipassInstance $WebServer | Out-Null

Write-Host "`nWaiting for VMs to settle..."
Start-Sleep -Seconds 5

Write-Host "`nStep 2: Resolving Multipass IP targets"
$DbIp = Resolve-LabTarget -Name $DbServer -Role "Database"
$AuthIp = Resolve-LabTarget -Name $AuthServer -Role "Auth"
$WebIp = Resolve-LabTarget -Name $WebServer -Role "Web"

if (-not [string]::IsNullOrWhiteSpace($AuthBase)) {
    Write-StaleIpDiagnostic -Name "Auth Server" -Url $AuthBase -DetectedIp $AuthIp
}
if (-not [string]::IsNullOrWhiteSpace($WebBase)) {
    Write-StaleIpDiagnostic -Name "Web Server" -Url $WebBase -DetectedIp $WebIp
}

if (-not [string]::IsNullOrWhiteSpace($AuthIp)) {
    $AuthBase = "http://${AuthIp}:8000"
}
if (-not [string]::IsNullOrWhiteSpace($WebIp)) {
    $WebBase = "http://$WebIp"
}

if ($AuthIp -and $AuthIp -ne "192.168.1.102") {
    Write-Diagnostic "Stale IP check: previous AuthBase used 192.168.1.102, current auth-server IP is $AuthIp."
}
if ($WebIp -and $WebIp -ne "192.168.1.109") {
    Write-Diagnostic "Stale IP check: previous WebBase used 192.168.1.109, current web-server IP is $WebIp."
}

Write-Host "`nResolved targets:"
Write-Host "auth-server IP: $AuthIp"
Write-Host "db-server IP:   $DbIp"
Write-Host "web-server IP:  $WebIp"
Write-Host "AuthBase:       $AuthBase"
Write-Host "WebBase:        $WebBase"

Write-Host "`nStep 3: Checking database service"
Ensure-Service $DbServer "postgresql" | Out-Null

Write-Host "`nStep 4: Checking and repairing app IP configuration"
$authConfigChanged = Update-AppIpConfig `
    -Name "Auth app" `
    -Instance $AuthServer `
    -Path "/home/ubuntu/auth-lab/app/main.py" `
    -ExpectedDbIp $DbIp

$webConfigChanged = Update-AppIpConfig `
    -Name "Web app" `
    -Instance $WebServer `
    -Path "/home/ubuntu/web-lab/app/main.py" `
    -ExpectedDbIp $DbIp `
    -ExpectedAuthIp $AuthIp

if ($authConfigChanged) {
    Write-Host "Restarting auth-lab after app config update..."
    Run-Cmd "multipass exec $AuthServer -- sudo systemctl restart auth-lab" | Out-Null
    Start-Sleep -Seconds 5
}
if ($webConfigChanged) {
    Write-Host "Restarting web-lab after app config update..."
    Run-Cmd "multipass exec $WebServer -- sudo systemctl restart web-lab" | Out-Null
    Start-Sleep -Seconds 5
}

Write-Host "`nStep 5: Checking application and proxy services"
Ensure-Service $AuthServer "auth-lab" | Out-Null
Ensure-Service $WebServer "web-lab" | Out-Null
Ensure-Service $WebServer "nginx" | Out-Null

Write-Host "`nStep 6: Checking HTTP health endpoints"
$authHealthUrl = if ($AuthBase) { "$AuthBase/health" } else { "" }
$webHealthUrl = if ($WebBase) { "$WebBase/health" } else { "" }

Test-HttpHealth `
    -Name "Auth Server" `
    -Url $authHealthUrl `
    -Instance $AuthServer `
    -PublicPort 8000 `
    -LocalHealthUrl "http://localhost:8000/health" `
    -ServiceName "auth-lab" `
    -DetectedIp $AuthIp | Out-Null

Test-HttpHealth `
    -Name "Web Server" `
    -Url $webHealthUrl `
    -Instance $WebServer `
    -PublicPort 80 `
    -LocalHealthUrl "http://localhost/health" `
    -ServiceName "web-lab" `
    -DetectedIp $WebIp `
    -CheckNginx | Out-Null

Write-Host "`nStep 7: Checking database schema"
Test-DbTables

if (-not $SkipLinkedEvidenceTest) {
    Write-Host "`nStep 8: Checking linked evidence"
    Test-LinkedEvidence | Out-Null
}
else {
    Write-Host "`nSkipping linked evidence test."
}

Show-SummaryAndExit
