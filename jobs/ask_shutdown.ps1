#Requires -Version 5.1
<#
  Popup shown in interactive session when idle watchdog asks to shut down.
  Yes -> allow scheduled shutdown to continue (or start /t 60)
  No  -> write cancel flag + shutdown /a + touch keepalive
#>
param(
  [string]$JobsRoot = "D:\FactorOS_Data\jobs"
)

$ErrorActionPreference = "Continue"
$CancelFile = Join-Path $JobsRoot "shutdown_cancel.flag"
$Keepalive = Join-Path $JobsRoot "keepalive"
$PendingFile = Join-Path $JobsRoot "shutdown_pending.json"

Add-Type -AssemblyName System.Windows.Forms | Out-Null
$msg = "电脑已空闲约 2 小时（无任务、无活动远程桌面）。`n`n要现在关机吗？`n`n• 点「否」= 继续使用，取消关机`n• 点「是」= 确认关机`n• 若不操作，约 1 小时后会自动关机"
$result = [System.Windows.Forms.MessageBox]::Show(
  $msg,
  "FactorOS 关机确认",
  [System.Windows.Forms.MessageBoxButtons]::YesNo,
  [System.Windows.Forms.MessageBoxIcon]::Question,
  [System.Windows.Forms.MessageBoxDefaultButton]::Button2
)

if ($result -eq [System.Windows.Forms.DialogResult]::No) {
  try { & shutdown.exe /a 2>$null | Out-Null } catch {}
  New-Item -ItemType Directory -Force -Path $JobsRoot | Out-Null
  Set-Content -Path $CancelFile -Value ((Get-Date).ToString("o")) -Encoding ascii
  Set-Content -Path $Keepalive -Value ((Get-Date).ToString("o")) -Encoding ascii
  Remove-Item -Force $PendingFile -ErrorAction SilentlyContinue
  [System.Windows.Forms.MessageBox]::Show("已取消关机，电脑将保持开机。", "FactorOS") | Out-Null
} else {
  # Yes — shut down sooner
  try { & shutdown.exe /a 2>$null | Out-Null } catch {}
  & shutdown.exe /s /t 30 /c "FactorOS: 用户确认关机"
}
