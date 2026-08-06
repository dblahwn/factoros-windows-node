# FactorOS Windows 存储节点 — 配置清单

本仓库用于在 **Windows 家用台式机** 上配置 FactorOS 的「**磁盘 + 轻/中量脚本**」节点。三机协同见 [WORK_SPLIT.md](./WORK_SPLIT.md)：

| 角色 | 机器 | 网络 | 说明 |
|------|------|------|------|
| 交互 / 编排 | Mac | WiFi `192.168.13.105` | Cursor UI、轻量编辑；盘/内存紧 |
| 存储 / 轻脚本 | Windows（`factoros-win`） | 有线 `192.168.1.114` | `D:\FactorOS_Data` + `D:\dev\FactorOS`；**非**主力算力 |
| 重算力 | Cloud `compshare-gpu` | Mac `~/.ssh/config` | 全历史 / fleet / LLM·RFT |

> **双网段：** Mac 可留在 `192.168.13.x`、Win 在 `192.168.1.x`。以 Mac→Win SSH/SMB 为准；Win ping 不通 Mac 通常是防火墙/ICMP，不阻塞协作。

**FactorOS 主仓库**（GitHub 为源码真相）：`git@github.com:dblahwn/FactorOS.git`

---

## 开始前：必读

1. **先修网络**：Windows 外网极慢时，Git/Python 安装会失败。请按 [NETWORK_FIX.md](./NETWORK_FIX.md) 排查（VPN/代理、网卡链路速度等）。
2. **以管理员身份运行 PowerShell** 执行自动化脚本（见下文）。
3. 本仓库 **不含** 任何私钥或 `.env`；Mac 的 **公钥** 会写入 Windows 的 `authorized_keys`（仅用于 SSH 登录授权）。

---

## 快速路径（推荐）

### 1. 安装基础软件（手动或 winget）

在 **管理员 PowerShell** 中：

```powershell
# Git
winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements

# Python 3.12（或你需要的版本）
winget install --id Python.Python.3.12 -e --accept-source-agreements --accept-package-agreements
```

安装后 **重新打开** PowerShell，确认：

```powershell
git --version
python --version
```

从 GitHub 克隆 **本配置仓库**（HTTPS 即可，无需 SSH）：

```powershell
cd $env:USERPROFILE
git clone https://github.com/dblahwn/factoros-windows-node.git
cd factoros-windows-node
```

### 2. 运行自动化脚本

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\setup.ps1
```

脚本会尝试：

- 安装/启用 **OpenSSH Server**（失败时仍继续写密钥/防火墙，便于 sshd 已存在的机器）
- 创建数据目录（优先 `D:\FactorOS_Data`，否则 `C:\FactorOS_Data`）及 `data`/`cache`/`backtest_results`
- 将 Mac 开发机的 **SSH 公钥** 写入 `authorized_keys`（**UTF-8 无 BOM**）
- 若已装 Git：把 `C:\Program Files\Git\bin`（及 `cmd`）写入 **Machine PATH**，供 Cursor Remote-SSH 找 `bash`
- 打印 SMB 共享与防火墙的后续步骤

### 3. 启用远程桌面（RDP）

**设置 → 系统 → 远程桌面 → 启用远程桌面**（便于 Mac 上图形排障）。

建议：仅允许 **局域网** 访问；强密码或 Windows Hello。

### 4. 配置 SMB 共享（若脚本未全自动完成）

1. 在资源管理器中右键 `D:\FactorOS_Data`（或 `C:\FactorOS_Data`）→ **属性** → **共享** → **高级共享**。
2. 勾选「共享此文件夹」，共享名例如：`FactorOS_Data`。
3. **权限**：给你的 Windows 登录用户「完全控制」（或按需只读+写入）。
4. 在 **Windows 防火墙** 中允许「文件和打印机共享」（专用网络）。

### 5. 防火墙：SSH

若 Mac 无法 SSH 连接，在管理员 PowerShell：

```powershell
New-NetFirewallRule -DisplayName "OpenSSH Server (sshd)" -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow
```

确认 SSH 服务：

```powershell
Get-Service sshd
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic
```

### 6. 克隆 FactorOS（代码仓 ≠ 数据盘）

**路径约定（强制）：**

| 用途 | 路径 |
|------|------|
| 代码仓 | `D:\dev\FactorOS` |
| 数据 / 缓存 / 回测产物 | `D:\FactorOS_Data\{data,cache,backtest_results}` |

**不要**把仓库 clone 进 `D:\FactorOS_Data`。若 Windows 尚无代码树，先配置 GitHub SSH 密钥（**在 Windows 上生成新密钥**，公钥加到 GitHub；**不要把私钥提交到任何仓库**），再：

```powershell
New-Item -ItemType Directory -Force -Path D:\dev | Out-Null
cd D:\dev
git clone git@github.com:dblahwn/FactorOS.git
```

Mac / Windows 分工见 [WORK_SPLIT.md](./WORK_SPLIT.md)。

---

## Mac 侧下一步

Windows 就绪后，在 Mac 上按 [MAC_CONNECT.md](./MAC_CONNECT.md) 配置：

- SSH `~/.ssh/config`
- SMB 挂载数据盘 `FactorOS_Data`（不是代码仓）
- （可选）Cursor / VS Code Remote SSH → 打开 `D:\dev\FactorOS`

---

## 文件说明

| 文件 | 用途 |
|------|------|
| `setup.ps1` | Windows 一键基础配置 |
| `WORK_SPLIT.md` | Mac ↔ Windows 分工与路径约定 |
| `NETWORK_FIX.md` | 外网慢 / 链路问题排查 |
| `MAC_CONNECT.md` | Mac 连接本节点的命令与习惯用法 |
| `CONNECT.md` | Cursor Remote 速查 |
| `SHARED_STATUS.md` | 双端进度对齐 |

---

## 安全提醒

- `authorized_keys` 里只有 **Mac 的公钥**，可公开说明其存在，但勿把 **Mac 私钥** 复制到 Windows。
- SMB 与 RDP 仅在可信局域网开启；路由器上避免把 3389/445 端口暴露到公网。
- FactorOS 数据库路径、API 密钥等只放在本机，不进 Git。

---

## 故障联系清单

- [ ] 同一局域网能否 `ping 192.168.1.114`（Mac → Windows）
- [ ] `ssh user@192.168.1.114` 是否提示密码或直接进入（密钥配置后应免密）
- [ ] SMB：`\\192.168.1.114\FactorOS_Data` 能否在 Mac 访达中打开
- [ ] 外网：`curl -I https://github.com` 在 Windows 上是否在几秒内返回

完成以上后，即可把 Windows 作为 FactorOS 的大容量存储与轻量脚本节点使用；重型回测走 Cloud `compshare-gpu`（见 [WORK_SPLIT.md](./WORK_SPLIT.md)）。
