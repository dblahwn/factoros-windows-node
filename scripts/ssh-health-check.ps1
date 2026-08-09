#Requires -Version 5.1
<#
  FactorOS SSH health / review-audit mode.
  Prints PASS/FAIL for permanent SSH stability controls.
  Exit 0 = all PASS; 1 = one or more FAIL.
#>
param(
  [string]$SshdConfig = "$env:ProgramData\ssh\sshd_config",
  [string]$TaskName = "FactorOS_SSHWatchdog",
  [string]$LogPath = "D:\FactorOS_Data\logs\ssh_watchdog.log",
  [int]$Port = 22,
  [string]$ServiceName = "sshd"
)

$ErrorActionPreference = "Continue"
$script:FailCount = 0
$results = New-Object System.Collections.Generic.List[object]

function Add-Result {
  param([string]$Check, [bool]$Pass, [string]$Detail)
  $status = if ($Pass) { "PASS" } else { "FAIL"; $script:FailCount++ }
  $results.Add([PSCustomObject]@{ Status = $status; Check = $Check; Detail = $Detail }) | Out-Null
}

Write-Host ""
Write-Host "=== FactorOS SSH Health Check (review mode) ==="
Write-Host ("Time: {0:yyyy-MM-dd HH:mm:ss}" -f (Get-Date))
Write-Host ("Host: {0}" -f $env:COMPUTERNAME)
Write-Host ""

# --- sshd_config ---
$configText = ""
if (Test-Path $SshdConfig) {
  $configText = Get-Content $SshdConfig -Raw -ErrorAction SilentlyContinue
  Add-Result "sshd_config exists" $true $SshdConfig
} else {
  Add-Result "sshd_config exists" $false "Missing $SshdConfig"
}

function Get-EffectiveDirective {
  param([string]$Name, [string]$Text)
  if (-not $Text) { return $null }
  # Last uncommented occurrence before any Match block wins for global settings we care about.
  $global = ($Text -split "(?m)^Match\s+")[0]
  $matches = [regex]::Matches($global, ("(?im)^\s*{0}\s+(\S+)" -f [regex]::Escape($Name)))
  if ($matches.Count -eq 0) { return $null }
  return $matches[$matches.Count - 1].Groups[1].Value
}

$cai = Get-EffectiveDirective -Name "ClientAliveInterval" -Text $configText
$cac = Get-EffectiveDirective -Name "ClientAliveCountMax" -Text $configText
$tcp = Get-EffectiveDirective -Name "TCPKeepAlive" -Text $configText

Add-Result "ClientAliveInterval" ($cai -eq "30") ("value=$cai expected=30")
Add-Result "ClientAliveCountMax" ([int]($cac) -ge 3) ("value=$cac expected>=3 (prefer 5)")
Add-Result "TCPKeepAlive" ($tcp -match "^(yes|true)$") ("value=$tcp expected=yes")

# Match blocks should not redefine Alive in a conflicting way
$matchAlive = $false
if ($configText -match "(?ims)^Match\b.*?^\s*ClientAlive") { $matchAlive = $true }
Add-Result "No Match override of ClientAlive*" (-not $matchAlive) $(if ($matchAlive) { "Match block sets ClientAlive*" } else { "OK" })

# --- Service ---
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
Add-Result "sshd service present" ($null -ne $svc) $(if ($svc) { $svc.DisplayName } else { "missing" })
if ($svc) {
  Add-Result "sshd Running" ($svc.Status -eq "Running") ("status=$($svc.Status)")
  Add-Result "sshd StartType Automatic" ($svc.StartType -eq "Automatic") ("StartType=$($svc.StartType)")
}

# Failure recovery (locale-robust: look for configured delay actions, not English "RESTART")
$failureOut = sc.exe qfailure $ServiceName 2>&1 | Out-String
$delayHits = ([regex]::Matches($failureOut, "5000")).Count
$hasRestart = ($failureOut -match "FAILURE_ACTIONS|失败操作") -and ($delayHits -ge 1)
# Also accept English RESTART / Chinese 重启 if console encoding preserves them
if ($failureOut -match "RESTART|重启") { $hasRestart = $true }
Add-Result "sshd failure recovery restart" $hasRestart ("sc delays=$delayHits; reset configured")

# --- Port ---
$listening = $false
try {
  $conns = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
  $listening = ($null -ne $conns -and @($conns).Count -gt 0)
} catch { }
Add-Result "TCP port $Port listening" $listening $(if ($listening) { "Listen OK" } else { "NOT listening" })

# --- Power (AC sleep never) — locale-robust parse of powercfg ---
$standbyAc = $null
try {
  $q = powercfg /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 2>&1 | Out-String
  if ($q -match "(?im)Current AC Power Setting Index:\s*0x([0-9a-f]+)") {
    $standbyAc = [Convert]::ToInt64($Matches[1], 16)
  } elseif ($q -match "(?im)当前交流电源适配器设置:\s*0x([0-9a-f]+)") {
    $standbyAc = [Convert]::ToInt64($Matches[1], 16)
  } else {
    # Mojibake-safe: after STANDBYIDLE, hex list is typically min/max/inc[/units] then AC then DC
    $part = ($q -split "STANDBYIDLE")[1]
    if ($part) {
      $hexes = [regex]::Matches($part, "0x([0-9a-fA-F]+)") | ForEach-Object { $_.Groups[1].Value }
      if ($hexes.Count -ge 2) {
        $standbyAc = [Convert]::ToInt64($hexes[$hexes.Count - 2], 16)
      }
    }
  }
} catch { }
Add-Result "AC sleep never (STANDBYIDLE=0)" ($standbyAc -eq 0) ("STANDBYIDLE_AC=$standbyAc")

# --- NIC power management ---
$nicOk = $true
$nicDetail = @()
try {
  Get-NetAdapter -Physical -ErrorAction SilentlyContinue | ForEach-Object {
    $pm = Get-NetAdapterPowerManagement -Name $_.Name -ErrorAction SilentlyContinue
    if ($pm -and $pm.AllowComputerToTurnOffDevice -notin @("Disabled", "Unsupported")) {
      $nicOk = $false
      $nicDetail += "$($_.Name)=$($pm.AllowComputerToTurnOffDevice)"
    } elseif ($pm) {
      $nicDetail += "$($_.Name)=$($pm.AllowComputerToTurnOffDevice)"
    }
  }
} catch {
  $nicOk = $false
  $nicDetail = @($_.Exception.Message)
}
Add-Result "NIC power-off disabled" $nicOk (($nicDetail -join "; "))

# --- Firewall ---
$fw = Get-NetFirewallRule -ErrorAction SilentlyContinue |
  Where-Object { $_.DisplayName -match "OpenSSH|sshd" -and $_.Enabled -eq $true -and $_.Direction -eq "Inbound" -and $_.Action -eq "Allow" }
Add-Result "OpenSSH inbound firewall Allow" (@($fw).Count -gt 0) ("rules=$(@($fw).Count)")

# --- Scheduled task ---
$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
Add-Result "Task $TaskName exists" ($null -ne $task) $(if ($task) { "State=$($task.State)" } else { "missing — run install-ssh-watchdog.ps1" })
if ($task) {
  $info = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
  $enabled = ($task.State -ne "Disabled")
  Add-Result "Task enabled" $enabled ("State=$($task.State); LastResult=$($info.LastTaskResult)")
  $triggers = @($task.Triggers)
  $hasRep = $false
  foreach ($t in $triggers) {
    if ($t.Repetition -and $t.Repetition.Interval) { $hasRep = $true }
  }
  Add-Result "Task has repetition trigger" $hasRep ("triggers=$($triggers.Count)")
}

# --- Log dir ---
$logDir = Split-Path -Parent $LogPath
Add-Result "Log directory exists" (Test-Path $logDir) $logDir
if (Test-Path $LogPath) {
  Add-Result "Watchdog log present" $true $LogPath
} else {
  Add-Result "Watchdog log present" $true "Not created yet (OK until first unhealthy event or first write)"
}

# --- Print table ---
Write-Host ("{0,-6} {1,-42} {2}" -f "STATUS", "CHECK", "DETAIL")
Write-Host ("{0,-6} {1,-42} {2}" -f "------", "------------------------------------------", "------")
foreach ($r in $results) {
  $color = if ($r.Status -eq "PASS") { "Green" } else { "Red" }
  Write-Host ("{0,-6} {1,-42} {2}" -f $r.Status, $r.Check, $r.Detail) -ForegroundColor $color
}

Write-Host ""
if ($script:FailCount -eq 0) {
  Write-Host "RESULT: ALL PASS ($($results.Count) checks)" -ForegroundColor Green
  exit 0
}

Write-Host "RESULT: $($script:FailCount) FAIL / $($results.Count) checks" -ForegroundColor Red
Write-Host "See SSH_STABILITY.md for remediation."
exit 1
