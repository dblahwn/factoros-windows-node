#Requires -Version 5.1
<#
  FactorOS Windows idle watchdog (headless + RDP safe).

  Flow:
    - Active RDP/console (EN Active / ZH 活动) OR jobs OR keepalive -> stay on
    - Idle >= IdleHours (default 2h) AND no Active user -> ASK (pending + shutdown /t 3600)
    - User says No / shutdown /a / keepalive / becomes Active -> cancel, reset timer
    - No reply for ReplyWaitHours (default 1h) after ask -> shutdown proceeds
#>
param(
  [string]$JobsRoot = "D:\FactorOS_Data\jobs",
  [double]$IdleHours = 2,
  [double]$ReplyWaitHours = 1,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Worker = Join-Path $ScriptDir "worker_once.ps1"
$AskScript = Join-Path $ScriptDir "ask_shutdown.ps1"
$StateFile = Join-Path $JobsRoot "watchdog_state.json"
$Keepalive = Join-Path $JobsRoot "keepalive"
$PendingFile = Join-Path $JobsRoot "shutdown_pending.json"
$CancelFile = Join-Path $JobsRoot "shutdown_cancel.flag"
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
    try { return Get-Content $StateFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
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

function Test-InteractiveSessionActive {
  # Prefer UTF-8 qwinsta so EN "Active" / ZH states parse reliably.
  try {
    $lines = & cmd.exe /c "chcp 65001 >nul & qwinsta" 2>$null
    foreach ($line in $lines) {
      $s = ("$line").Trim()
      if (-not $s -or $s -match '(?i)SESSIONNAME') { continue }
      if ($s -match '(?i)Listen|Listener') { continue }
      if ($s -match '(?i)\bDisc\b|Disconnected') { continue }
      if ($s -match '(?i)\bActive\b') { return $true }
      # Chinese Active (活动/活動) via codepoints
      if ($s.Contains([char]0x6D3B) -and ($s.Contains([char]0x52A8) -or $s.Contains([char]0x52D5))) { return $true }
      # Fallback: named user on a real session (not services/rdp-tcp listener)
      # e.g. "console  Administrator  1  ..."
      if ($s -match '(?i)^(console|rdp-tcp#\d+|\S+)\s+(\S+)\s+(\d+)\s+') {
        $user = $Matches[2]
        $id = [int]$Matches[3]
        if ($user -and $user -notmatch '(?i)^(USERNAME)?$' -and $id -lt 65535 -and $id -gt 0) {
          return $true
        }
      }
    }
  } catch {}
  return $false
}

function Abort-PendingShutdown {
  try { & shutdown.exe /a 2>$null | Out-Null } catch {}
  Remove-Item -Force $PendingFile -ErrorAction SilentlyContinue
  Remove-Item -Force $CancelFile -ErrorAction SilentlyContinue
  try { Unregister-ScheduledTask -TaskName "FactorOS_AskShutdown" -Confirm:$false -ErrorAction SilentlyContinue } catch {}
}

function Show-AskPopup {
  if (-not (Test-Path $AskScript)) {
    Write-Log "ask_shutdown.ps1 missing — Windows shutdown dialog only"
    return
  }
  try { Unregister-ScheduledTask -TaskName "FactorOS_AskShutdown" -Confirm:$false -ErrorAction SilentlyContinue } catch {}
  $arg = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File `"$AskScript`" -JobsRoot `"$JobsRoot`""
  try {
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $arg
    $trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddSeconds(8))
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    $user = $env:USERNAME
    if ($user -and $user -ne "SYSTEM") {
      try {
        $prin = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
        Register-ScheduledTask -TaskName "FactorOS_AskShutdown" -Action $action -Trigger $trigger -Principal $prin -Settings $settings -Force | Out-Null
        Start-ScheduledTask -TaskName "FactorOS_AskShutdown" -ErrorAction SilentlyContinue
        Write-Log ("scheduled ask popup as {0}" -f $user)
        return
      } catch {
        Write-Log ("schedule as user failed: {0}" -f $_.Exception.Message)
      }
    }
    $tr = "powershell.exe $arg"
    & schtasks.exe /Create /TN "FactorOS_AskShutdown" /TR $tr /SC ONCE /ST ((Get-Date).AddMinutes(1).ToString("HH:mm")) /RL HIGHEST /F /IT 2>$null | Out-Null
    & schtasks.exe /Run /TN "FactorOS_AskShutdown" 2>$null | Out-Null
    Write-Log "scheduled ask popup via schtasks /IT"
  } catch {
    Write-Log ("ask popup schedule error: {0}" -f $_.Exception.Message)
  }
}

function Start-AskShutdown {
  param([datetime]$Deadline)
  $pending = [ordered]@{
    asked_at     = (Get-Date).ToString("o")
    deadline     = $Deadline.ToString("o")
    idle_hours   = $IdleHours
    reply_hours  = $ReplyWaitHours
    reason       = "idle_no_jobs_no_active_session"
  }
  ($pending | ConvertTo-Json) | Set-Content -Path $PendingFile -Encoding utf8
  Remove-Item -Force $CancelFile -ErrorAction SilentlyContinue

  $secs = [math]::Max(60, [int](($Deadline - (Get-Date)).TotalSeconds))
  Write-Log ("ASK shutdown: pending until {0:o} (t={1}s)" -f $Deadline, $secs)
  if ($DryRun) {
    Write-Log "DryRun: skip shutdown / popup"
    return
  }
  $cmt = "FactorOS idle {0}h. Cancel: shutdown /a or click No. Auto-shutdown in ~{1}h if no reply." -f $IdleHours, $ReplyWaitHours
  & shutdown.exe /s /t $secs /c $cmt
  Show-AskPopup
}

Ensure-Dirs

$interactive = Test-InteractiveSessionActive

if (Test-Path $CancelFile) {
  Write-Log "cancel flag present -> abort pending, stay on"
  Abort-PendingShutdown
  Touch-Activity
  exit 0
}

if ($interactive) {
  if (Test-Path $PendingFile) { Write-Log "Active session during pending ask -> abort" }
  Abort-PendingShutdown
  Touch-Activity
  Write-Log "user present (Active session) -> stay on"
}

$inboxItems = @(Get-ChildItem (Join-Path $JobsRoot "inbox") -Filter "*.json" -ErrorAction SilentlyContinue)
$runningItems = @(Get-ChildItem (Join-Path $JobsRoot "running") -Filter "*.json" -ErrorAction SilentlyContinue)

if ($inboxItems.Count -gt 0) {
  Abort-PendingShutdown
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
  Abort-PendingShutdown
  Write-Log ("running={0} -> stay on" -f $runningItems.Count)
  Touch-Activity
  exit 0
}

if ($interactive) {
  Write-Log "stay on (user activity)"
  exit 0
}

$now = Get-Date
$state = Read-State
$lastAct = $now
try { $lastAct = [datetime]::Parse($state.last_activity) } catch {}
$kaTime = $lastAct
if (Test-Path $Keepalive) { $kaTime = (Get-Item $Keepalive).LastWriteTime }
$ref = $lastAct
if ($kaTime -gt $ref) { $ref = $kaTime }
$idle = $now - $ref

Write-Log ("idle={0:N2}h thr={1}h last_act={2:o} keepalive={3:o} interactive={4} pending={5}" -f `
  $idle.TotalHours, $IdleHours, $lastAct, $kaTime, $interactive, (Test-Path $PendingFile))

if (Test-Path $PendingFile) {
  $p = $null
  try { $p = Get-Content $PendingFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
  $deadline = $now.AddHours($ReplyWaitHours)
  try { if ($p -and $p.deadline) { $deadline = [datetime]::Parse($p.deadline) } } catch {}

  if (Test-InteractiveSessionActive) {
    Abort-PendingShutdown
    Touch-Activity
    Write-Log "pending aborted — user became Active"
    exit 0
  }

  if ($now -lt $deadline) {
    Write-Log ("pending ask — waiting reply until {0:o}" -f $deadline)
    exit 0
  }

  Write-Log "pending deadline passed — forcing shutdown /t 60"
  if (-not $DryRun) {
    & shutdown.exe /a 2>$null | Out-Null
    & shutdown.exe /s /t 60 /c "FactorOS: shutdown confirm timed out (1h no reply)"
  }
  exit 0
}

if ($idle.TotalHours -ge $IdleHours) {
  if (Test-InteractiveSessionActive) {
    Touch-Activity
    Write-Log "abort ask — interactive appeared"
    exit 0
  }
  $deadline = $now.AddHours($ReplyWaitHours)
  Start-AskShutdown -Deadline $deadline
  exit 0
}

Write-Log "stay on"
exit 0
