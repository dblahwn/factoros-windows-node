# FactorOS Windows Node - baseline setup
# Run as Administrator in PowerShell:
#   Set-ExecutionPolicy -Scope Process Bypass; .\setup.ps1

$ErrorActionPreference = "Stop"

$MacPubKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAKuYvPB7HczopUEnnlYTsMjYTP2WCKu5svXWlqhg/6F 424549466@qq.com"

function Write-Step($msg) {
    Write-Host "`n==> $msg" -ForegroundColor Cyan
}

function Test-IsAdmin {
    $current = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($current)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    Write-Warning "请右键 PowerShell，选择「以管理员身份运行」，再执行本脚本。"
    exit 1
}

Write-Step "检测数据目录（优先 D:）"
$dataRoot = $null
if (Test-Path "D:\") {
    $dataRoot = "D:\FactorOS_Data"
} else {
    $dataRoot = "C:\FactorOS_Data"
}
New-Item -ItemType Directory -Force -Path $dataRoot | Out-Null
Write-Host "数据根目录: $dataRoot"

Write-Step "安装/启用 OpenSSH Server"
$sshCapability = Get-WindowsCapability -Online | Where-Object { $_.Name -like "OpenSSH.Server*" }
if ($sshCapability -and $sshCapability.State -ne "Installed") {
    Add-WindowsCapability -Online -Name $sshCapability.Name
} elseif (-not $sshCapability) {
    Write-Warning "未找到 OpenSSH.Server 可选功能，请通过 设置 -> 应用 -> 可选功能 手动安装 OpenSSH 服务器。"
}

$sshdService = Get-Service -Name sshd -ErrorAction SilentlyContinue
if ($sshdService) {
    Set-Service -Name sshd -StartupType Automatic
    if ($sshdService.Status -ne "Running") { Start-Service sshd }
    Write-Host "sshd 服务已设为自动启动。"
} else {
    Write-Warning "sshd 服务不存在，请确认 OpenSSH Server 已安装。"
}

Write-Step "配置 Mac 开发机 SSH 公钥"
$sshDir = Join-Path $env:ProgramData "ssh"
if (-not (Test-Path $sshDir)) { New-Item -ItemType Directory -Force -Path $sshDir | Out-Null }

$adminKeys = Join-Path $sshDir "administrators_authorized_keys"
$authKeys = Join-Path $env:USERPROFILE ".ssh\authorized_keys"

foreach ($path in @($adminKeys, $authKeys)) {
    $parent = Split-Path $path -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $content = @()
    if (Test-Path $path) { $content = Get-Content $path -ErrorAction SilentlyContinue }
    if ($content -notcontains $MacPubKey) {
        Add-Content -Path $path -Value $MacPubKey -Encoding utf8
        Write-Host "已追加公钥到: $path"
    } else {
        Write-Host "公钥已存在: $path"
    }
}

# OpenSSH on Windows often uses administrators_authorized_keys for admin users
icacls $adminKeys /inheritance:r 2>$null | Out-Null
icacls $adminKeys /grant "SYSTEM:(F)" 2>$null | Out-Null
icacls $adminKeys /grant "BUILTIN\Administrators:(F)" 2>$null | Out-Null

Write-Step "防火墙：允许 TCP 22（若规则不存在）"
$ruleName = "OpenSSH Server (sshd) FactorOS"
$existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
if (-not $existing) {
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow | Out-Null
    Write-Host "已添加防火墙入站规则: $ruleName"
}

Write-Step "SMB 共享提示（需手动确认权限）"
Write-Host @"

请在资源管理器中：
  1. 右键 $dataRoot -> 属性 -> 共享 -> 高级共享
  2. 共享名建议: FactorOS_Data
  3. 权限：为你的 Windows 账户授予「更改/读取」或「完全控制」

Mac 挂载路径示例: \\$((Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like '192.168.*' } | Select-Object -First 1).IPAddress)\FactorOS_Data

"@

Write-Step "建议安装的软件（若尚未安装）"
Write-Host @"
  winget install Git.Git
  winget install Python.Python.3.12

远程桌面：设置 -> 系统 -> 远程桌面 -> 启用

网络仍慢请先阅读本仓库 NETWORK_FIX.md

Mac 连接说明见 MAC_CONNECT.md

本机 IP（IPv4 局域网）:
"@
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "127.*" -and $_.PrefixOrigin -ne "WellKnown" } |
    Select-Object InterfaceAlias, IPAddress | Format-Table -AutoSize

Write-Host "`n完成。请在 Mac 上测试: ssh $env:USERNAME@<Windows_IP>" -ForegroundColor Green
