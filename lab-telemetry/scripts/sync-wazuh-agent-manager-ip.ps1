<#
.SYNOPSIS
Synchronizes Wazuh endpoint agent manager IPs with the current Multipass wazuh-server IP.

.DESCRIPTION
Multipass bridged DHCP addresses can change. This script detects the current Wazuh manager
instance IP, updates only the Wazuh agent manager <server><address> value on endpoint VMs,
backs up ossec.conf before editing, optionally restarts wazuh-agent, and prints connection
status from endpoint logs plus active-agent status from the manager.

.EXAMPLE
.\scripts\sync-wazuh-agent-manager-ip.ps1 -WhatIf

.EXAMPLE
.\scripts\sync-wazuh-agent-manager-ip.ps1
#>

[CmdletBinding()]
param(
    [string]$WazuhInstance = "wazuh-server",

    [string[]]$AgentInstances = @("auth-server", "web-server", "db-server"),

    [switch]$SkipRestart,

    [switch]$WhatIf
)

$ErrorActionPreference = "Continue"

$OssecConfPath = "/var/ossec/etc/ossec.conf"
$OssecLogPath = "/var/ossec/logs/ossec.log"
$Timestamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$BackupPath = "$OssecConfPath.bak-before-manager-ip-sync-$Timestamp"
$script:Results = New-Object System.Collections.Generic.List[object]

function Write-Step {
    param([string]$Message)
    Write-Host ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Message)
}

function Add-Result {
    param(
        [string]$Instance,
        [string]$Step,
        [ValidateSet("PASS", "WARN", "FAIL", "SKIP")]
        [string]$Status,
        [string]$Details = ""
    )

    $script:Results.Add([PSCustomObject]@{
        Instance = $Instance
        Step = $Step
        Status = $Status
        Details = $Details
    }) | Out-Null

    $color = switch ($Status) {
        "PASS" { "Green" }
        "WARN" { "Yellow" }
        "FAIL" { "Red" }
        "SKIP" { "DarkYellow" }
    }
    Write-Host "[$Status] $Instance - $Step $Details" -ForegroundColor $color
}

function Invoke-LocalCommand {
    param([scriptblock]$Command)

    try {
        $output = & $Command 2>&1
        return [PSCustomObject]@{
            ExitCode = if ($null -ne $global:LASTEXITCODE) { $global:LASTEXITCODE } else { if ($?) { 0 } else { 1 } }
            Output = @($output)
        }
    }
    catch {
        return [PSCustomObject]@{
            ExitCode = 1
            Output = @($_.Exception.Message)
        }
    }
}

function Invoke-MultipassBash {
    param(
        [string]$Instance,
        [string]$Script
    )

    $global:LASTEXITCODE = $null
    return Invoke-LocalCommand -Command {
        & multipass exec $Instance -- bash -lc $Script
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
    $infoResult = Invoke-LocalCommand -Command {
        & multipass info --format json $Name
    }

    if ($infoResult.ExitCode -eq 0) {
        try {
            $json = ($infoResult.Output -join "`n") | ConvertFrom-Json -ErrorAction Stop
            $instanceInfo = $json.info.PSObject.Properties[$Name].Value
            if ($instanceInfo -and $instanceInfo.ipv4) {
                $candidates += @($instanceInfo.ipv4)
            }
        }
        catch {
            # Fall back to text parsing below.
        }
    }

    if ($candidates.Count -eq 0) {
        $textResult = Invoke-LocalCommand -Command {
            & multipass info $Name
        }
        if ($textResult.ExitCode -eq 0) {
            $candidates += @(
                [regex]::Matches(($textResult.Output -join "`n"), "(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])") |
                    ForEach-Object { $_.Value }
            )
        }
    }

    if ($candidates.Count -eq 0) {
        $listResult = Invoke-LocalCommand -Command {
            & multipass list
        }
        if ($listResult.ExitCode -eq 0) {
            $line = (($listResult.Output -join "`n") -split "`n" | Where-Object { $_ -match "^\s*$Name\s+" } | Select-Object -First 1)
            if ($line) {
                $candidates += @(
                    [regex]::Matches($line, "(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])") |
                        ForEach-Object { $_.Value }
                )
            }
        }
    }

    return Select-LabIPv4 -Candidates $candidates
}

function Test-MultipassInstanceRunning {
    param([string]$Name)

    $listResult = Invoke-LocalCommand -Command {
        & multipass list
    }

    if ($listResult.ExitCode -ne 0) {
        return [PSCustomObject]@{
            Exists = $false
            Running = $false
            Details = ($listResult.Output -join "`n")
        }
    }

    $line = (($listResult.Output -join "`n") -split "`n" | Where-Object { $_ -match "^\s*$Name\s+" } | Select-Object -First 1)
    if (-not $line) {
        return [PSCustomObject]@{
            Exists = $false
            Running = $false
            Details = "Instance not found"
        }
    }

    return [PSCustomObject]@{
        Exists = $true
        Running = ($line -match "\sRunning\s")
        Details = $line.Trim()
    }
}

function Get-CurrentManagerAddress {
    param([string]$Instance)

    $script = @'
set -e
conf="/var/ossec/etc/ossec.conf"
sudo python3 - "$conf" <<'PY'
import re
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8", errors="replace").read()
match = re.search(r"<server\b[^>]*>.*?<address>([^<]+)</address>.*?</server>", text, re.S)
if not match:
    sys.exit(2)
print(match.group(1).strip())
PY
'@

    return Invoke-MultipassBash -Instance $Instance -Script $script
}

function Update-AgentManagerAddress {
    param(
        [string]$Instance,
        [string]$ManagerIp
    )

    $script = @'
set -e
conf="__OSSEC_CONF_PATH__"
backup="__BACKUP_PATH__"
manager_ip="__MANAGER_IP__"
sudo cp -p "$conf" "$backup"
tmp_file=$(mktemp)
sudo python3 - "$conf" "$tmp_file" "$manager_ip" <<'PY'
import re
import sys

path = sys.argv[1]
out_path = sys.argv[2]
manager_ip = sys.argv[3]
text = open(path, encoding="utf-8", errors="replace").read()
pattern = re.compile(r"(<server\b[^>]*>.*?<address>)([^<]+)(</address>.*?</server>)", re.S)
new_text, count = pattern.subn(lambda m: m.group(1) + manager_ip + m.group(3), text, count=1)
if count != 1:
    sys.stderr.write("Could not find exactly one editable Wazuh manager server/address block\n")
    sys.exit(2)
open(out_path, "w", encoding="utf-8").write(new_text)
PY
sudo install -o root -g ossec -m 0640 "$tmp_file" "$conf" 2>/dev/null || sudo install -o root -g root -m 0644 "$tmp_file" "$conf"
rm -f "$tmp_file"
sudo python3 - "$conf" <<'PY'
import re
import sys

text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
match = re.search(r"<server\b[^>]*>.*?<address>([^<]+)</address>.*?</server>", text, re.S)
if not match:
    sys.exit(2)
print(match.group(1).strip())
PY
'@

    $script = $script.Replace("__OSSEC_CONF_PATH__", $OssecConfPath).
        Replace("__BACKUP_PATH__", $BackupPath).
        Replace("__MANAGER_IP__", $ManagerIp)

    return Invoke-MultipassBash -Instance $Instance -Script $script
}

function Restart-WazuhAgent {
    param([string]$Instance)

    $script = @'
set -e
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart wazuh-agent
  sudo systemctl is-active wazuh-agent
else
  sudo service wazuh-agent restart
  sudo service wazuh-agent status >/dev/null
  echo active
fi
'@

    return Invoke-MultipassBash -Instance $Instance -Script $script
}

function Read-AgentConnectionStatus {
    param(
        [string]$Instance,
        [string]$ManagerIp
    )

    $script = @'
set +e
manager_ip="__MANAGER_IP__"
log_path="__OSSEC_LOG_PATH__"
if [ ! -f "$log_path" ]; then
  echo "ossec.log missing: $log_path"
  exit 0
fi
echo "--- recent manager/address lines ---"
sudo tail -n 250 "$log_path" | grep -Ei "connected|manager|server|address|${manager_ip}" | tail -n 30
echo "--- current manager ip match ---"
if sudo tail -n 500 "$log_path" | grep -F "$manager_ip" >/dev/null 2>&1; then
  echo "FOUND_CURRENT_MANAGER_IP=$manager_ip"
else
  echo "CURRENT_MANAGER_IP_NOT_SEEN=$manager_ip"
fi
'@

    $script = $script.Replace("__MANAGER_IP__", $ManagerIp).
        Replace("__OSSEC_LOG_PATH__", $OssecLogPath)

    return Invoke-MultipassBash -Instance $Instance -Script $script
}

function Show-ManagerActiveAgents {
    param([string]$Instance)

    $script = "sudo /var/ossec/bin/agent_control -lc"
    return Invoke-MultipassBash -Instance $Instance -Script $script
}

Write-Host "============================================================"
Write-Host "Coding Fest 2026 XDR Wazuh Agent Manager IP Sync"
Write-Host "============================================================"
Write-Host "WazuhInstance:  $WazuhInstance"
Write-Host "AgentInstances: $($AgentInstances -join ', ')"
Write-Host "SkipRestart:    $([bool]$SkipRestart)"
Write-Host "WhatIf:         $([bool]$WhatIf)"

$wazuhState = Test-MultipassInstanceRunning -Name $WazuhInstance
if (-not $wazuhState.Exists -or -not $wazuhState.Running) {
    Add-Result -Instance $WazuhInstance -Step "Wazuh instance running" -Status "FAIL" -Details $wazuhState.Details
    $script:Results | Format-Table -AutoSize -Wrap
    exit 1
}
Add-Result -Instance $WazuhInstance -Step "Wazuh instance running" -Status "PASS" -Details $wazuhState.Details

$managerIp = Get-MultipassIPv4 -Name $WazuhInstance
if ([string]::IsNullOrWhiteSpace($managerIp)) {
    Add-Result -Instance $WazuhInstance -Step "Detect manager IP" -Status "FAIL" -Details "Could not detect current IPv4 from multipass info/list"
    $script:Results | Format-Table -AutoSize -Wrap
    exit 1
}
Add-Result -Instance $WazuhInstance -Step "Detect manager IP" -Status "PASS" -Details $managerIp

$hardFailure = $false

foreach ($agent in $AgentInstances) {
    Write-Host "`n============================================================"
    Write-Host "Agent endpoint: $agent"
    Write-Host "============================================================"

    $agentState = Test-MultipassInstanceRunning -Name $agent
    if (-not $agentState.Exists -or -not $agentState.Running) {
        Add-Result -Instance $agent -Step "Agent instance running" -Status "FAIL" -Details $agentState.Details
        $hardFailure = $true
        continue
    }
    Add-Result -Instance $agent -Step "Agent instance running" -Status "PASS" -Details $agentState.Details

    $currentAddress = Get-CurrentManagerAddress -Instance $agent
    if ($currentAddress.ExitCode -eq 0) {
        Add-Result -Instance $agent -Step "Current ossec.conf manager address" -Status "PASS" -Details (($currentAddress.Output | Select-Object -Last 1) -join "")
    }
    else {
        Add-Result -Instance $agent -Step "Current ossec.conf manager address" -Status "FAIL" -Details ($currentAddress.Output -join "`n")
        $hardFailure = $true
        continue
    }

    if ($WhatIf) {
        Add-Result -Instance $agent -Step "Update ossec.conf" -Status "SKIP" -Details "WhatIf: would backup to $BackupPath and set manager address to $managerIp"
        if (-not $SkipRestart) {
            Add-Result -Instance $agent -Step "Restart wazuh-agent" -Status "SKIP" -Details "WhatIf"
        }
        continue
    }

    Write-Step "Backing up and updating $agent ossec.conf"
    $update = Update-AgentManagerAddress -Instance $agent -ManagerIp $managerIp
    if ($update.ExitCode -ne 0) {
        Add-Result -Instance $agent -Step "Update ossec.conf" -Status "FAIL" -Details ($update.Output -join "`n")
        $hardFailure = $true
        continue
    }

    $updatedAddress = (($update.Output | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Last 1) -join "")
    if ($updatedAddress -eq $managerIp) {
        Add-Result -Instance $agent -Step "Update ossec.conf" -Status "PASS" -Details "manager=$updatedAddress backup=$BackupPath"
    }
    else {
        Add-Result -Instance $agent -Step "Update ossec.conf" -Status "FAIL" -Details "Expected $managerIp but read $updatedAddress"
        $hardFailure = $true
        continue
    }

    if ($SkipRestart) {
        Add-Result -Instance $agent -Step "Restart wazuh-agent" -Status "SKIP" -Details "SkipRestart specified"
    }
    else {
        Write-Step "Restarting wazuh-agent on $agent"
        $restart = Restart-WazuhAgent -Instance $agent
        if ($restart.ExitCode -eq 0) {
            Add-Result -Instance $agent -Step "Restart wazuh-agent" -Status "PASS" -Details (($restart.Output | Select-Object -Last 3) -join " ")
            Start-Sleep -Seconds 3
        }
        else {
            Add-Result -Instance $agent -Step "Restart wazuh-agent" -Status "FAIL" -Details ($restart.Output -join "`n")
            $hardFailure = $true
            continue
        }
    }

    $logStatus = Read-AgentConnectionStatus -Instance $agent -ManagerIp $managerIp
    if ($logStatus.ExitCode -eq 0) {
        $logText = $logStatus.Output -join "`n"
        $status = if ($logText -match "FOUND_CURRENT_MANAGER_IP=$([regex]::Escape($managerIp))") { "PASS" } else { "WARN" }
        Add-Result -Instance $agent -Step "Recent ossec.log manager IP" -Status $status -Details ($(if ($status -eq "PASS") { "found $managerIp" } else { "current manager IP not seen in recent log tail" }))
        Write-Host $logText
    }
    else {
        Add-Result -Instance $agent -Step "Recent ossec.log manager IP" -Status "WARN" -Details ($logStatus.Output -join "`n")
    }
}

Write-Host "`n============================================================"
Write-Host "Wazuh manager active agents"
Write-Host "============================================================"
$activeAgents = Show-ManagerActiveAgents -Instance $WazuhInstance
if ($activeAgents.ExitCode -eq 0) {
    Add-Result -Instance $WazuhInstance -Step "agent_control -lc" -Status "PASS" -Details "Listed active agents"
    $activeAgents.Output | ForEach-Object { Write-Host $_ }
}
else {
    Add-Result -Instance $WazuhInstance -Step "agent_control -lc" -Status "WARN" -Details ($activeAgents.Output -join "`n")
}

Write-Host "`n============================================================"
Write-Host "SUMMARY"
Write-Host "============================================================"
$script:Results | Format-Table -AutoSize -Wrap

if ($hardFailure) {
    Write-Host "`nWazuh agent manager IP sync failed. Review FAIL rows above." -ForegroundColor Red
    exit 1
}

Write-Host "`nWazuh agent manager IP sync completed." -ForegroundColor Green
exit 0
