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
Copy-Item -Force (Join-Path $SourceDir "watchdog.ps1") (Join-Path $InstallDir "watchdog.ps1")
Copy-Item -Force (Join-Path $SourceDir "worker_once.ps1") (Join-Path $InstallDir "worker_once.ps1")
Copy-Item -Force (Join-Path $SourceDir "JOB_PROTOCOL.md") (Join-Path $InstallDir "JOB_PROTOCOL.md") -ErrorAction SilentlyContinue

# Ensure jobs tree + keepalive
$JobsRoot = "D:\FactorOS_Data\jobs"
foreach ($d in @("inbox", "running", "outbox", "failed", "logs")) {
  New-Item -ItemType Directory -Force -Path (Join-Path $JobsRoot $d) | Out-Null
}
$ka = Join-Path $JobsRoot "keepalive"
if (-not (Test-Path $ka)) {
  Set-Content -Path $ka -Value ("installed {0:o}" -f (Get-Date)) -Encoding ascii
}

$taskName = "FactorOS_IdleWatchdog"
$watchdog = Join-Path $InstallDir "watchdog.ps1"
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $watchdog)
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration ([TimeSpan]::MaxValue)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null

Write-Output "Installed task $taskName"
Write-Output "Scripts: $InstallDir"
Write-Output "Jobs: $JobsRoot"
Write-Output "Idle shutdown: 2 hours (see watchdog.ps1 -IdleHours)"

# Kick once
& powershell -NoProfile -ExecutionPolicy Bypass -File $watchdog
