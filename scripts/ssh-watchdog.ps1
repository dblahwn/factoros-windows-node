#Requires -Version 5.1
<#
  FactorOS SSH watchdog — keep OpenSSH listening on port 22.
  Intended to run as SYSTEM via scheduled task FactorOS_SSHWatchdog every 1–2 minutes.
#>
param(
  [string]$LogPath = "D:\FactorOS_Data\logs\ssh_watchdog.log",
  [int]$Port = 22,
  [string]$ServiceName = "sshd"
)

$ErrorActionPreference = "Continue"

function Write-Log {
  param([string]$Message, [string]$Level = "INFO")
  $line = "{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}" -f (Get-Date), $Level, $Message
  try {
    $dir = Split-Path -Parent $LogPath
    if ($dir -and -not (Test-Path $dir)) {
      New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Add-Content -Path $LogPath -Value $line -Encoding utf8
  } catch {
    # Best-effort logging; never fail the watchdog solely because of log I/O.
  }
  Write-Output $line
}

function Test-SshListening {
  param([int]$ListenPort)
  try {
    $listeners = Get-NetTCPConnection -LocalPort $ListenPort -State Listen -ErrorAction SilentlyContinue
    return ($null -ne $listeners -and @($listeners).Count -gt 0)
  } catch {
    # Fallback: netstat parse
    $raw = netstat -an | Select-String -Pattern (":{0}\s+.*LISTENING" -f $ListenPort)
    return ($null -ne $raw)
  }
}

$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $svc) {
  Write-Log "Service '$ServiceName' not found" "ERROR"
  exit 2
}

$listening = Test-SshListening -ListenPort $Port
$svcRunning = ($svc.Status -eq "Running")

if ($svcRunning -and $listening) {
  # Healthy — quiet success (optional heartbeat every run would spam logs)
  exit 0
}

$reasons = @()
if (-not $svcRunning) { $reasons += "service_status=$($svc.Status)" }
if (-not $listening) { $reasons += "port_${Port}_not_listening" }
Write-Log ("Unhealthy: {0} - attempting Start-Service {1}" -f ($reasons -join "; "), $ServiceName) "WARN"

try {
  if ($svc.Status -eq "StopPending") {
    Start-Sleep -Seconds 3
    $svc.Refresh()
  }
  if ($svc.Status -ne "Running") {
    Start-Service -Name $ServiceName -ErrorAction Stop
  } else {
    # Running but not listening — bounce once
    Write-Log "Service running but port not listening — Restart-Service" "WARN"
    Restart-Service -Name $ServiceName -Force -ErrorAction Stop
  }
} catch {
  Write-Log ("Failed to start/restart {0}: {1}" -f $ServiceName, $_.Exception.Message) "ERROR"
  exit 1
}

Start-Sleep -Seconds 2
$svc.Refresh()
$listeningAfter = Test-SshListening -ListenPort $Port
$ok = ($svc.Status -eq "Running") -and $listeningAfter

if ($ok) {
  Write-Log "Recovered: sshd Running and port $Port listening" "INFO"
  exit 0
}

Write-Log ("Recovery incomplete: status={0} listening={1}" -f $svc.Status, $listeningAfter) "ERROR"
exit 1
