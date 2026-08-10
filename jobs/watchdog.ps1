#Requires -Version 5.1
<#
  FactorOS Windows idle watchdog (overnight headless safe).

  Stay-on (abort pending ask; do NOT reset idle unless real presence):
    A. Active RDP session (rdp-tcp#N Active / 活动) — user is remoted in
    B. Console/RDP session with RECENT input (quser IDLE TIME < IdleHours)
    C. inbox/running jobs, or keepalive mtime within IdleHours
    D. cancel flag / CANCEL_SHUTDOWN.bat / shutdown /a

  Explicitly NOT stay-on forever:
    - explorer / Cursor / other apps left running with no recent input
    - console still labeled Active but idle for hours (ghost session)
    - rdp-tcp Listen (listener only)

  Ask flow (only when none of the above stay-on):
    Idle >= IdleHours -> pending + shutdown /s /t 3600 + popup/msg
    No reply for ReplyWaitHours -> force shutdown /t 60
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
$CancelBat = Join-Path $ScriptDir "CANCEL_SHUTDOWN.bat"
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

function ConvertTo-IdleHours([string]$raw) {
  # quser IDLE TIME: ".", "none", "无", "0", "12", "1:23", "1+02:15"
  if (-not $raw) { return 0.0 }
  $t = $raw.Trim().TrimStart('>', ' ')
  if ($t -match '(?i)^(none|\.|无|-)$') { return 0.0 }
  if ($t -match '^(\d+)\+([0-9]+):([0-9]+)$') {
    return [double]$Matches[1] * 24.0 + [double]$Matches[2] + ([double]$Matches[3] / 60.0)
  }
  if ($t -match '^([0-9]+):([0-9]+)$') {
    return [double]$Matches[1] + ([double]$Matches[2] / 60.0)
  }
  if ($t -match '^([0-9]+)$') {
    return [double]$Matches[1] / 60.0  # minutes
  }
  return 0.0
}

function Get-SessionPresence {
  <#
    Returns presence object:
      RdpActive   - live RDP (rdp-tcp#N Active)
      RecentInput - any interactive session with idle < IdleHours
      Present     - RdpActive OR RecentInput (true stay-on)
      Detail      - short log string
    Does NOT treat leftover apps (Cursor/explorer) as presence.
  #>
  $rdpActive = $false
  $recentInput = $false
  $details = @()

  # --- qwinsta: detect live RDP vs Listen vs Disc ---
  try {
    $qw = & cmd.exe /c "chcp 65001 >nul & qwinsta" 2>$null
    foreach ($line in $qw) {
      $s = ("$line").Trim()
      if (-not $s -or $s -match '(?i)SESSIONNAME') { continue }
      if ($s -match '(?i)rdp-tcp\s' -and $s -match '(?i)Listen') { continue }
      $isActive = ($s -match '(?i)\bActive\b') -or `
        ($s.Contains([char]0x6D3B) -and ($s.Contains([char]0x52A8) -or $s.Contains([char]0x52D5)))
      if (-not $isActive) { continue }
      if ($s -match '(?i)rdp-tcp#\d+') {
        $rdpActive = $true
        $details += "rdp_active"
      }
    }
  } catch {}

  # --- quser: IDLE TIME (hours since last input per session) ---
  $minIdleH = [double]::PositiveInfinity
  try {
    $qu = & cmd.exe /c "chcp 65001 >nul & quser" 2>$null
    foreach ($line in $qu) {
      $s = ("$line").Trim()
      if (-not $s -or $s -match '(?i)USERNAME') { continue }
      if ($s -match '(?i)\bDisc\b|Disconnected|断开') { continue }
      # Columns are space-padded; idle is 2nd-to-last before logon date. Parse tokens from end-ish.
      # Typical: USERNAME SESSIONNAME ID STATE IDLE_TIME LOGON_DATE LOGON_TIME
      $parts = @($s -replace '^\s*>?\s*', '' -split '\s+' | Where-Object { $_ })
      if ($parts.Count -lt 5) { continue }
      # Find STATE token (Active/活动) then next is idle
      $idleTok = $null
      for ($i = 0; $i -lt $parts.Count; $i++) {
        $tok = $parts[$i]
        $stateHit = ($tok -match '(?i)^(Active|活动|活動)$') -or `
          ($tok.Contains([char]0x6D3B) -and ($tok.Length -le 4))
        if ($stateHit -and ($i + 1) -lt $parts.Count) {
          $idleTok = $parts[$i + 1]
          break
        }
      }
      if (-not $idleTok) {
        # Fallback: token before date-like field
        for ($i = $parts.Count - 1; $i -ge 0; $i--) {
          if ($parts[$i] -match '^\d{1,4}([/-])\d{1,2}\1\d{1,4}$' -or $parts[$i] -match '^\d{4}/\d{1,2}/\d{1,2}$') {
            if ($i -ge 1) { $idleTok = $parts[$i - 1]; break }
          }
        }
      }
      if (-not $idleTok) { continue }
      $ih = ConvertTo-IdleHours $idleTok
      if ($ih -lt $minIdleH) { $minIdleH = $ih }
      $details += ("sess_idle={0:N2}h({1})" -f $ih, $idleTok)
    }
  } catch {}

  if ($minIdleH -lt [double]::PositiveInfinity -and $minIdleH -lt $IdleHours) {
    $recentInput = $true
  }

  # Live RDP always counts as present (even if quser idle parse fails)
  $present = ($rdpActive -or $recentInput)
  if ($rdpActive -and -not ($details -contains "rdp_active")) { $details += "rdp_active" }
  if (-not $present) { $details += "no_recent_presence" }

  return [pscustomobject]@{
    RdpActive   = $rdpActive
    RecentInput = $recentInput
    Present     = $present
    MinIdleH    = $(if ($minIdleH -lt [double]::PositiveInfinity) { $minIdleH } else { -1 })
    Detail      = ($details -join ";")
  }
}

function Abort-PendingShutdown {
  try { & shutdown.exe /a 2>$null | Out-Null } catch {}
  Remove-Item -Force $PendingFile -ErrorAction SilentlyContinue
  Remove-Item -Force $CancelFile -ErrorAction SilentlyContinue
  try { Unregister-ScheduledTask -TaskName "FactorOS_AskShutdown" -Confirm:$false -ErrorAction SilentlyContinue } catch {}
}

function Notify-CancelHint {
  $hint = "FactorOS: will shut down in ~1h if no reply. CANCEL: double-click C:\FactorOS\jobs\CANCEL_SHUTDOWN.bat  OR  shutdown /a  OR  Mac win_ctl.sh cancel-shutdown"
  try {
    & msg.exe * /TIME:120 $hint 2>$null | Out-Null
  } catch {}
  try {
    & msg.exe 1 /TIME:120 $hint 2>$null | Out-Null
  } catch {}
}

function Show-AskPopup {
  Notify-CancelHint
  if (-not (Test-Path $AskScript)) {
    Write-Log "ask_shutdown.ps1 missing — Windows shutdown dialog + msg only; use CANCEL_SHUTDOWN.bat"
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
    reason       = "idle_no_jobs_no_recent_presence"
    cancel_hint  = "C:\FactorOS\jobs\CANCEL_SHUTDOWN.bat or shutdown /a"
  }
  ($pending | ConvertTo-Json) | Set-Content -Path $PendingFile -Encoding utf8
  Remove-Item -Force $CancelFile -ErrorAction SilentlyContinue

  $secs = [math]::Max(60, [int](($Deadline - (Get-Date)).TotalSeconds))
  Write-Log ("ASK shutdown: pending until {0:o} (t={1}s)" -f $Deadline, $secs)
  if ($DryRun) {
    Write-Log "DryRun: skip shutdown / popup"
    return
  }
  $cmt = "FactorOS idle {0}h. CANCEL: C:\FactorOS\jobs\CANCEL_SHUTDOWN.bat OR shutdown /a OR click No. Auto in ~{1}h." -f $IdleHours, $ReplyWaitHours
  & shutdown.exe /s /t $secs /c $cmt
  Show-AskPopup
}

Ensure-Dirs

$presence = Get-SessionPresence
$present = [bool]$presence.Present

if (Test-Path $CancelFile) {
  Write-Log "cancel flag present -> abort pending, stay on"
  Abort-PendingShutdown
  Touch-Activity
  exit 0
}

# Real presence (RDP live or recent input): stay on and refresh activity.
# Leftover Cursor/explorer with stale input does NOT land here.
if ($present) {
  if (Test-Path $PendingFile) {
    Write-Log ("presence during pending -> abort ({0})" -f $presence.Detail)
  }
  Abort-PendingShutdown
  Touch-Activity
  Write-Log ("user present -> stay on ({0})" -f $presence.Detail)
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

if ($present) {
  Write-Log "stay on (recent presence)"
  exit 0
}

$now = Get-Date
$state = Read-State
$lastAct = $now
try { $lastAct = [datetime]::Parse($state.last_activity) } catch {}
$kaTime = $lastAct
if (Test-Path $Keepalive) { $kaTime = (Get-Item $Keepalive).LastWriteTime }

# Idle ref = most recent REAL signal (keepalive / last_activity).
# If quser says input idle >= IdleHours, ignore inflated last_activity from older
# builds that Touch-Activity'd every tick because Cursor/explorer were "busy".
$ref = $kaTime
if ($lastAct -gt $ref) { $ref = $lastAct }
if ($presence.MinIdleH -ge $IdleHours) {
  $ref = $kaTime
  Write-Log ("session input idle {0:N2}h >= thr — ignore last_activity, keepalive-only ref" -f $presence.MinIdleH)
} elseif ($presence.MinIdleH -ge 0) {
  $sessRef = $now.AddHours(-1.0 * $presence.MinIdleH)
  if ($sessRef -gt $ref) { $ref = $sessRef }
}
$idle = $now - $ref

Write-Log ("idle={0:N2}h thr={1}h last_act={2:o} keepalive={3:o} presence={4} min_sess_idle={5} pending={6}" -f `
  $idle.TotalHours, $IdleHours, $lastAct, $kaTime, $presence.Detail, $presence.MinIdleH, (Test-Path $PendingFile))

if (Test-Path $PendingFile) {
  $p = $null
  try { $p = Get-Content $PendingFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
  $deadline = $now.AddHours($ReplyWaitHours)
  try { if ($p -and $p.deadline) { $deadline = [datetime]::Parse($p.deadline) } } catch {}

  $again = Get-SessionPresence
  if ($again.Present) {
    Abort-PendingShutdown
    Touch-Activity
    Write-Log ("pending aborted — presence ({0})" -f $again.Detail)
    exit 0
  }
  if (Test-Path $CancelFile) {
    Abort-PendingShutdown
    Touch-Activity
    Write-Log "pending aborted — cancel flag"
    exit 0
  }

  if ($now -lt $deadline) {
    Write-Log ("pending ask — waiting reply until {0:o} (cancel: {1})" -f $deadline, $CancelBat)
    exit 0
  }

  $final = Get-SessionPresence
  if ($final.Present) {
    Abort-PendingShutdown
    Touch-Activity
    Write-Log ("pending deadline skipped — presence ({0})" -f $final.Detail)
    exit 0
  }

  Write-Log "pending deadline passed — forcing shutdown /t 60"
  if (-not $DryRun) {
    & shutdown.exe /a 2>$null | Out-Null
    & shutdown.exe /s /t 60 /c "FactorOS: confirm timed out. Last chance: CANCEL_SHUTDOWN.bat or shutdown /a"
    Notify-CancelHint
  }
  exit 0
}

if ($idle.TotalHours -ge $IdleHours) {
  $pre = Get-SessionPresence
  if ($pre.Present) {
    Touch-Activity
    Write-Log ("abort ask — presence appeared ({0})" -f $pre.Detail)
    exit 0
  }
  $deadline = $now.AddHours($ReplyWaitHours)
  Start-AskShutdown -Deadline $deadline
  exit 0
}

Write-Log "stay on (idle under threshold; leftover apps ignored)"
exit 0
