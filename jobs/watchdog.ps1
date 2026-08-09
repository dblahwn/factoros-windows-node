#Requires -Version 5.1
<#
  FactorOS Windows idle watchdog (headless + RDP safe).

  Stay-on (any one aborts pending ask, no new ask):
    A. Active interactive session (EN Active / ZH 活动) — RDP or console
    B. User apps running (SessionId>0, not system/shell noise)
    C. inbox/running jobs, or fresh keepalive
    D. cancel flag / shutdown /a / CANCEL_SHUTDOWN.bat

  Ask flow (only when none of the above):
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

# System / shell noise — never count as "user is busy"
$script:IdleNoiseNames = @(
  'Idle', 'System', 'Registry', 'smss', 'csrss', 'wininit', 'winlogon', 'services',
  'lsass', 'lsm', 'svchost', 'fontdrvhost', 'dwm', 'sihost', 'taskhostw',
  'RuntimeBroker', 'SearchHost', 'SearchApp', 'SearchUI', 'ShellExperienceHost',
  'StartMenuExperienceHost', 'TextInputHost', 'ctfmon', 'conhost', 'dllhost',
  'WmiPrvSE', 'ApplicationFrameHost', 'SystemSettings', 'SecurityHealthSystray',
  'SecurityHealthService', 'LockApp', 'UserOOBEBroker', 'backgroundTaskHost',
  'smartscreen', 'explorer', 'audiodg', 'spoolsv', 'SearchIndexer', 'taskeng',
  'ChsIME', 'TabTip', 'CrossDeviceService', 'PhoneExperienceHost', 'Widgets',
  'WidgetService', 'MicrosoftEdgeUpdate', 'msedgewebview2',
  # Our ask popup / scheduled helpers (visible FactorOS title skipped separately)
  'powershell', 'pwsh'
) | ForEach-Object { $_.ToLowerInvariant() }

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

function Test-UserAppsBusy {
  <#
    True if SessionId>0 has real user apps (not shell/system noise),
    or any process with a visible main window that is not our ask dialog.
  #>
  $busy = @()
  try {
    $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object {
      $_.SessionId -gt 0
    }
  } catch {
    return $false
  }

  foreach ($p in $procs) {
    $name = $p.ProcessName
    if (-not $name) { continue }
    $nl = $name.ToLowerInvariant()

    # Visible main window in user session (exclude our own ask MessageBox)
    $hasWin = $false
    try { $hasWin = ($p.MainWindowHandle -ne [IntPtr]::Zero) } catch {}
    if ($hasWin) {
      $title = ""
      try { $title = [string]$p.MainWindowTitle } catch {}
      if ($title -match '(?i)FactorOS') { continue }
      $busy += $name
      continue
    }

    if ($script:IdleNoiseNames -contains $nl) { continue }
    # Helper processes / crashpad noise
    if ($nl -match '(?i)helper|crashpad|gpu-process|renderer|Broker') { continue }

    $busy += $name
  }

  $uniq = @($busy | Select-Object -Unique)
  if ($uniq.Count -ge 1) {
    Write-Log ("userApps busy count={0} samples={1}" -f $uniq.Count, (($uniq | Select-Object -First 8) -join ','))
    return $true
  }
  return $false
}

function Test-UserBusy {
  $active = Test-InteractiveSessionActive
  $apps = Test-UserAppsBusy
  return [pscustomobject]@{
    ActiveSession = $active
    UserApps      = $apps
    Busy          = ($active -or $apps)
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
    # Also target console session 1 if present
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
    # SYSTEM context: try interactive task for logged-on user
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
    reason       = "idle_no_jobs_no_user_busy"
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

$user = Test-UserBusy
$interactive = [bool]$user.ActiveSession
$userApps = [bool]$user.UserApps
$userBusy = [bool]$user.Busy

if (Test-Path $CancelFile) {
  Write-Log "cancel flag present -> abort pending, stay on"
  Abort-PendingShutdown
  Touch-Activity
  exit 0
}

if ($userBusy) {
  if (Test-Path $PendingFile) {
    Write-Log ("userBusy during pending -> abort (active={0} apps={1})" -f $interactive, $userApps)
  }
  Abort-PendingShutdown
  Touch-Activity
  Write-Log ("user present -> stay on (active={0} apps={1})" -f $interactive, $userApps)
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

if ($userBusy) {
  Write-Log "stay on (user activity / apps)"
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

Write-Log ("idle={0:N2}h thr={1}h last_act={2:o} keepalive={3:o} active={4} apps={5} pending={6}" -f `
  $idle.TotalHours, $IdleHours, $lastAct, $kaTime, $interactive, $userApps, (Test-Path $PendingFile))

if (Test-Path $PendingFile) {
  $p = $null
  try { $p = Get-Content $PendingFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
  $deadline = $now.AddHours($ReplyWaitHours)
  try { if ($p -and $p.deadline) { $deadline = [datetime]::Parse($p.deadline) } } catch {}

  # Re-check stay-on conditions mid-pending
  $again = Test-UserBusy
  if ($again.Busy) {
    Abort-PendingShutdown
    Touch-Activity
    Write-Log ("pending aborted — userBusy (active={0} apps={1})" -f $again.ActiveSession, $again.UserApps)
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

  # Final stay-on gate before force
  $final = Test-UserBusy
  if ($final.Busy) {
    Abort-PendingShutdown
    Touch-Activity
    Write-Log "pending deadline skipped — user became busy"
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
  $pre = Test-UserBusy
  if ($pre.Busy) {
    Touch-Activity
    Write-Log ("abort ask — userBusy appeared (active={0} apps={1})" -f $pre.ActiveSession, $pre.UserApps)
    exit 0
  }
  $deadline = $now.AddHours($ReplyWaitHours)
  Start-AskShutdown -Deadline $deadline
  exit 0
}

Write-Log "stay on"
exit 0
