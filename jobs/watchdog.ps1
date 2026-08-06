#Requires -Version 5.1
<#
  FactorOS Windows idle watchdog.
  If no jobs (inbox/running) and keepalive mtime older than IdleHours, shutdown.
  Also drains one inbox job via worker_once.ps1 when work appears.
#>
param(
  [string]$JobsRoot = "D:\FactorOS_Data\jobs",
  [double]$IdleHours = 2,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Worker = Join-Path $ScriptDir "worker_once.ps1"
$StateFile = Join-Path $JobsRoot "watchdog_state.json"
$Keepalive = Join-Path $JobsRoot "keepalive"
$LogDir = Join-Path $JobsRoot "logs"
$LogFile = Join-Path $LogDir ("watchdog_{0:yyyyMMdd}.log" -f (Get-Date))

function Write-Log([string]$msg) {
  $line = "{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $msg
  try {
    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
    Add-Content -Path $LogFile -Value $line -Encoding utf8
  } catch {}
  Write-Output $line
}

function Ensure-Dirs {
  foreach ($d in @("inbox", "running", "outbox", "failed", "logs")) {
    New-Item -ItemType Directory -Force -Path (Join-Path $JobsRoot $d) | Out-Null
  }
  if (-not (Test-Path $Keepalive)) {
    Set-Content -Path $Keepalive -Value ("created {0:o}" -f (Get-Date)) -Encoding ascii
  }
}

function Read-State {
  if (Test-Path $StateFile) {
    try { return Get-Content $StateFile -Raw | ConvertFrom-Json } catch {}
  }
  return [pscustomobject]@{ last_activity = (Get-Date).ToString("o") }
}

function Write-State($state) {
  ($state | ConvertTo-Json) | Set-Content -Path $StateFile -Encoding utf8
}

function Touch-Activity {
  $state = Read-State
  $state | Add-Member -NotePropertyName last_activity -NotePropertyValue ((Get-Date).ToString("o")) -Force
  Write-State $state
}

Ensure-Dirs

# Drain work first
$inboxItems = @(Get-ChildItem (Join-Path $JobsRoot "inbox") -Filter "*.json" -ErrorAction SilentlyContinue)
$runningItems = @(Get-ChildItem (Join-Path $JobsRoot "running") -Filter "*.json" -ErrorAction SilentlyContinue)

if ($inboxItems.Count -gt 0) {
  Write-Log ("inbox={0} -> run worker" -f $inboxItems.Count)
  Touch-Activity
  if (Test-Path $Worker) {
    try {
      & powershell -NoProfile -ExecutionPolicy Bypass -File $Worker -JobsRoot $JobsRoot
      Touch-Activity
    } catch {
      Write-Log ("worker error: {0}" -f $_.Exception.Message)
    }
  } else {
    Write-Log "worker_once.ps1 missing"
  }
  exit 0
}

if ($runningItems.Count -gt 0) {
  Write-Log ("running={0} -> stay on" -f $runningItems.Count)
  Touch-Activity
  exit 0
}

# Idle check
$now = Get-Date
$state = Read-State
$lastAct = $now
try { $lastAct = [datetime]::Parse($state.last_activity) } catch {}

$kaTime = $lastAct
if (Test-Path $Keepalive) {
  $kaTime = (Get-Item $Keepalive).LastWriteTime
}

$ref = $lastAct
if ($kaTime -gt $ref) { $ref = $kaTime }

$idle = $now - $ref
Write-Log ("idle={0:N1}h (threshold={1}h) last_act={2:o} keepalive={3:o}" -f $idle.TotalHours, $IdleHours, $lastAct, $kaTime)

if ($idle.TotalHours -ge $IdleHours) {
  Write-Log "IDLE -> shutdown /s /t 30"
  if ($DryRun) {
    Write-Log "DryRun: skip shutdown"
    exit 0
  }
  shutdown.exe /s /t 30 /c "FactorOS watchdog: idle ${IdleHours}h"
  exit 0
}

Write-Log "stay on"
exit 0
