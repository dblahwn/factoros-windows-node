#Requires -Version 5.1
<#
  Install FactorOS SSH watchdog scheduled task (every 2 minutes).
  Run elevated: powershell -ExecutionPolicy Bypass -File install-ssh-watchdog.ps1
#>
param(
  [string]$InstallDir = "C:\FactorOS\ssh",
  [string]$SourceDir = "",
  [int]$IntervalMinutes = 2,
  [string]$LogPath = "D:\FactorOS_Data\logs\ssh_watchdog.log"
)

$ErrorActionPreference = "Stop"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw "Run elevated (Administrator)."
}

if (-not $SourceDir) {
  $SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath) | Out-Null

$srcWatchdog = Join-Path $SourceDir "ssh-watchdog.ps1"
if (-not (Test-Path $srcWatchdog)) {
  throw "Missing $srcWatchdog"
}
Copy-Item -Force $srcWatchdog (Join-Path $InstallDir "ssh-watchdog.ps1")
Copy-Item -Force (Join-Path $SourceDir "ssh-health-check.ps1") (Join-Path $InstallDir "ssh-health-check.ps1") -ErrorAction SilentlyContinue

$taskName = "FactorOS_SSHWatchdog"
$watchdog = Join-Path $InstallDir "ssh-watchdog.ps1"
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`" -LogPath `"{1}`"" -f $watchdog, $LogPath)
# Avoid [TimeSpan]::MaxValue — some Windows builds reject Duration:P99999999DT23H59M59S
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
  -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) `
  -RepetitionDuration (New-TimeSpan -Days 3650)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet `
  -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries `
  -StartWhenAvailable `
  -MultipleInstances IgnoreNew `
  -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null

# Harden sshd service recovery (idempotent)
sc.exe config sshd start= auto | Out-Null
sc.exe failure sshd reset= 86400 actions= restart/5000/restart/5000/restart/5000 | Out-Null
sc.exe failureflag sshd 1 | Out-Null

Write-Output "Installed task $taskName (every $IntervalMinutes min)"
Write-Output "Script: $watchdog"
Write-Output "Log: $LogPath"

# Kick once
& powershell -NoProfile -ExecutionPolicy Bypass -File $watchdog -LogPath $LogPath
