#Requires -Version 5.1
<#
  Consume one job from inbox -> running -> outbox/failed.
#>
param(
  [string]$JobsRoot = "D:\FactorOS_Data\jobs"
)

$ErrorActionPreference = "Stop"
$Inbox = Join-Path $JobsRoot "inbox"
$Running = Join-Path $JobsRoot "running"
$Outbox = Join-Path $JobsRoot "outbox"
$Failed = Join-Path $JobsRoot "failed"

foreach ($d in @($Inbox, $Running, $Outbox, $Failed)) {
  New-Item -ItemType Directory -Force -Path $d | Out-Null
}

$jobFile = Get-ChildItem $Inbox -Filter "*.json" -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime |
  Select-Object -First 1

if (-not $jobFile) {
  Write-Output "no inbox jobs"
  exit 0
}

$raw = Get-Content $jobFile.FullName -Raw -Encoding UTF8
$job = $raw | ConvertFrom-Json
$id = $job.id
if (-not $id) { $id = [io.path]::GetFileNameWithoutExtension($jobFile.Name) }

$destRunning = Join-Path $Running ($id + ".json")
Move-Item -Force $jobFile.FullName $destRunning

$cwd = "D:\dev\FactorOS"
if ($job.cwd) { $cwd = [string]$job.cwd }
$timeout = 7200
if ($job.timeout_sec) { $timeout = [int]$job.timeout_sec }
$cmd = [string]$job.cmd
if (-not $cmd) {
  throw "job missing cmd"
}

$started = Get-Date
$outDir = Join-Path $Outbox $id
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$stdoutLog = Join-Path $outDir "stdout.log"
$stderrLog = Join-Path $outDir "stderr.log"

$p = Start-Process -FilePath "cmd.exe" -ArgumentList @("/c", $cmd) `
  -WorkingDirectory $cwd -PassThru -NoNewWindow `
  -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog

$exited = $p.WaitForExit([Math]::Max(1000, $timeout * 1000))
$finished = Get-Date
$status = "ok"
$exitCode = 1

if (-not $exited) {
  try { if (-not $p.HasExited) { $p.Kill() } } catch {}
  $status = "timeout"
  $exitCode = -9
} else {
  # Ensure async redirected streams are flushed and ExitCode is populated
  try { $p.WaitForExit() | Out-Null } catch {}
  if ($null -eq $p.ExitCode) {
    $exitCode = 0
  } else {
    $exitCode = [int]$p.ExitCode
  }
  if ($exitCode -ne 0) { $status = "error" }
}

$result = [ordered]@{
  id           = $id
  status       = $status
  exit_code    = $exitCode
  started_at   = $started.ToString("o")
  finished_at  = $finished.ToString("o")
  cmd          = $cmd
  cwd          = $cwd
  stdout_log   = "stdout.log"
  stderr_log   = "stderr.log"
}

$finalDir = $outDir
if ($status -ne "ok") {
  $finalDir = Join-Path $Failed $id
  if (Test-Path $finalDir) { Remove-Item -Recurse -Force $finalDir }
  Move-Item -Force $outDir $finalDir
}

($result | ConvertTo-Json -Depth 5) | Set-Content -Path (Join-Path $finalDir "result.json") -Encoding utf8
Remove-Item -Force $destRunning -ErrorAction SilentlyContinue
Write-Output ("done id={0} status={1} exit={2}" -f $id, $status, $exitCode)
