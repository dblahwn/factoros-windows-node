#Requires -Version 5.1
<#
  Install FactorOS idle watchdog as a scheduled task (every 5 minutes).
  Run elevated: powershell -ExecutionPolicy Bypass -File install_watchdog.ps1
#>
param(
  [string]$InstallDir = "C:\FactorOS\jobs",
  [string]$SourceDir = ""
)

$ErrorActionPreference = "Stop"

if (-not $SourceDir) {
  $SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
$srcNorm = [System.IO.Path]::GetFullPath($SourceDir).TrimEnd('\')
$dstNorm = [System.IO.Path]::GetFullPath($InstallDir).TrimEnd('\')
if ($srcNorm -ne $dstNorm) {
  Copy-Item -Force (Join-Path $SourceDir "watchdog.ps1") (Join-Path $InstallDir "watchdog.ps1")
  Copy-Item -Force (Join-Path $SourceDir "worker_once.ps1") (Join-Path $InstallDir "worker_once.ps1")
  Copy-Item -Force (Join-Path $SourceDir "ask_shutdown.ps1") (Join-Path $InstallDir "ask_shutdown.ps1") -ErrorAction SilentlyContinue
  Copy-Item -Force (Join-Path $SourceDir "CANCEL_SHUTDOWN.bat") (Join-Path $InstallDir "CANCEL_SHUTDOWN.bat") -ErrorAction SilentlyContinue
  Copy-Item -Force (Join-Path $SourceDir "JOB_PROTOCOL.md") (Join-Path $InstallDir "JOB_PROTOCOL.md") -ErrorAction SilentlyContinue
} else {
  Write-Output "SourceDir == InstallDir; skip copy (already deployed)"
}

# Ensure jobs tree + keepalive
$JobsRoot = "D:\FactorOS_Data\jobs"
foreach ($d in @("inbox", "running", "outbox", "failed", "logs")) {
  New-Item -ItemType Directory -Force -Path (Join-Path $JobsRoot $d) | Out-Null
}
$ka = Join-Path $JobsRoot "keepalive"
if (-not (Test-Path $ka)) {
  Set-Content -Path $ka -Value ("installed {0:o}" -f (Get-Date)) -Encoding ascii
}

# Desktop shortcut for easy cancel (all interactive users' Public Desktop + current user)
$cancelBat = Join-Path $InstallDir "CANCEL_SHUTDOWN.bat"
function New-CancelShortcut([string]$LinkPath) {
  if (-not (Test-Path $cancelBat)) { return }
  try {
    $dir = Split-Path -Parent $LinkPath
    if (-not (Test-Path $dir)) { return }
    $w = New-Object -ComObject WScript.Shell
    $sc = $w.CreateShortcut($LinkPath)
    $sc.TargetPath = $cancelBat
    $sc.WorkingDirectory = $InstallDir
    $sc.WindowStyle = 1
    $sc.Description = "Cancel FactorOS idle shutdown (shutdown /a + keepalive)"
    $sc.Save()
  } catch {}
}
New-CancelShortcut "C:\Users\Public\Desktop\取消 FactorOS 关机.lnk"
if ($env:USERPROFILE) {
  New-CancelShortcut (Join-Path $env:USERPROFILE "Desktop\取消 FactorOS 关机.lnk")
}

$taskName = "FactorOS_IdleWatchdog"
$watchdog = Join-Path $InstallDir "watchdog.ps1"
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $watchdog)
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null

Write-Output "Installed task $taskName"
Write-Output "Scripts: $InstallDir"
Write-Output "Jobs: $JobsRoot"
Write-Output "Cancel: $cancelBat (+ Public Desktop shortcut)"
Write-Output "Idle shutdown: 2 hours (see watchdog.ps1 -IdleHours)"

# Abort any pending shutdown from older logic, then kick once
try { & shutdown.exe /a 2>$null | Out-Null } catch {}
Remove-Item -Force (Join-Path $JobsRoot "shutdown_pending.json") -ErrorAction SilentlyContinue
# Clear inflated last_activity from older "apps=busy forever" builds so overnight
# idle can start cleanly after deploy (keepalive still respected by watchdog).
$statePath = Join-Path $JobsRoot "watchdog_state.json"
$stale = [ordered]@{
  last_activity = (Get-Date).AddHours(-3).ToString("o")
  note          = "reset_on_install_overnight_fix"
}
($stale | ConvertTo-Json) | Set-Content -Path $statePath -Encoding utf8
Write-Output "Reset watchdog_state.json last_activity to -3h (keepalive still wins if fresher)"
& powershell -NoProfile -ExecutionPolicy Bypass -File $watchdog
