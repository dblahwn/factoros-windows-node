#Requires -Version 5.1
<#
  Popup shown in interactive session when idle watchdog asks to shut down.
  Yes -> confirm shutdown (/t 30)
  No  -> shutdown /a + cancel flag + clear pending + touch keepalive
#>
param(
  [string]$JobsRoot = "D:\FactorOS_Data\jobs"
)

$ErrorActionPreference = "Continue"
$CancelFile = Join-Path $JobsRoot "shutdown_cancel.flag"
$Keepalive = Join-Path $JobsRoot "keepalive"
$PendingFile = Join-Path $JobsRoot "shutdown_pending.json"
$CancelBat = "C:\FactorOS\jobs\CANCEL_SHUTDOWN.bat"

function Invoke-CancelShutdown {
  New-Item -ItemType Directory -Force -Path $JobsRoot | Out-Null
  # Write cancel flag FIRST so next watchdog tick stays on even if /a races
  Set-Content -Path $CancelFile -Value ((Get-Date).ToString("o")) -Encoding ascii
  Set-Content -Path $Keepalive -Value ((Get-Date).ToString("o")) -Encoding ascii
  Remove-Item -Force $PendingFile -ErrorAction SilentlyContinue
  try { & shutdown.exe /a 2>$null | Out-Null } catch {}
  # Second /a in case first raced with a new timer
  Start-Sleep -Milliseconds 400
  try { & shutdown.exe /a 2>$null | Out-Null } catch {}
}

Add-Type -AssemblyName System.Windows.Forms | Out-Null
$msg = @(
  "电脑疑似空闲约 2 小时（无任务、无 RDP、无近期键鼠输入）。",
  "后台残留 Cursor/explorer 不会阻止自动关机。",
  "",
  "要现在关机吗？",
  "",
  "• 点「否」= 继续使用，取消关机",
  "• 点「是」= 确认关机",
  "• 若不操作，约 1 小时后会自动关机",
  "",
  "若本对话框无响应，请双击桌面「取消 FactorOS 关机」",
  "或运行: $CancelBat",
  "或命令: shutdown /a"
) -join "`n"

try {
  $result = [System.Windows.Forms.MessageBox]::Show(
    $msg,
    "FactorOS 关机确认",
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Question,
    [System.Windows.Forms.MessageBoxDefaultButton]::Button2
  )
} catch {
  # MessageBox failed (no interactive desktop) — leave shutdown timer; user can use CANCEL bat / msg
  try {
    & msg.exe * /TIME:180 "FactorOS ask failed to show. CANCEL: $CancelBat or shutdown /a" 2>$null | Out-Null
  } catch {}
  exit 0
}

if ($result -eq [System.Windows.Forms.DialogResult]::No) {
  Invoke-CancelShutdown
  try {
    [System.Windows.Forms.MessageBox]::Show("已取消关机，电脑将保持开机。", "FactorOS") | Out-Null
  } catch {}
} elseif ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
  try { & shutdown.exe /a 2>$null | Out-Null } catch {}
  & shutdown.exe /s /t 30 /c "FactorOS: 用户确认关机"
} else {
  # Unexpected / closed — treat as cancel for safety (prefer stay-on)
  Invoke-CancelShutdown
}
