# SSH 长连接稳定性方案（Mac ↔ Windows）

**节点：** Windows `192.168.1.114`（OpenSSH Server）← Mac Remote-SSH / CLI  
**目标：** 连接极少掉线；若掉线，Windows 侧在约 1–2 分钟内自愈（恢复监听）。  
**更新：** 2026-08-09

---

## 1. Goal / Non-goals

### Goal

| # | 目标 |
|---|------|
| G1 | **永久**配置：sshd keepalive、电源/网卡不休眠、服务失败自动重启、定时 watchdog |
| G2 | 空闲 30+ 分钟仍保持会话（双侧 keepalive） |
| G3 | sshd 崩溃或端口 22 未监听时，**≤2 分钟**内重启服务并写日志 |
| G4 | **Review/审计模式**：一键脚本输出 PASS/FAIL，可复检 |
| G5 | 文档固化坑点与选型，避免后人重复踩坑 |

### Non-goals

| # | 不做 |
|---|------|
| N1 | **不**用 mosh 作为 Cursor Remote-SSH 传输（Cursor 只认 SSH） |
| N2 | **不**用临时手工命令当“修好了”（拒绝临时补丁） |
| N3 | **不**指望 keepalive 在客户端换 IP / 跨网段漫游后仍保活同一条 TCP（TCP 四元组变了就死） |
| N4 | **不**把 `MaxStartups` / `LoginGraceTime` 当成“防掉线”旋钮乱改 |
| N5 | 不与现有 `FactorOS_IdleWatchdog`（2h 空闲关机）冲突；SSH watchdog 只保 sshd |

---

## 2. 选定架构（Primary + Fallback Self-heal）

```
┌──────── Mac ─────────────────────────────────────────┐
│  ~/.ssh/config                                       │
│    ServerAliveInterval 30                            │
│    ServerAliveCountMax 5                             │
│    TCPKeepAlive yes                                  │
│    (可选) ControlMaster / ControlPersist 多路复用    │
│  Cursor Remote-SSH → 标准 SSH（非 mosh）             │
└─────────────────────────┬────────────────────────────┘
                          │ TCP :22 + app-level keepalive
┌─────────────────────────▼────────────────────────────┐
│  Windows OpenSSH (sshd)                              │
│    ClientAliveInterval 30 / ClientAliveCountMax 5    │
│    TCPKeepAlive yes                                  │
│    服务: Automatic + 失败后重启                      │
│    电源: AC 永不睡眠；NIC 禁止节能关机               │
│                                                      │
│  Fallback self-heal:                                 │
│    Task Scheduler FactorOS_SSHWatchdog @ 1–2 min     │
│    → scripts/ssh-watchdog.ps1                        │
│    → 端口 22 未听 或 sshd Stopped → Start-Service    │
│    → 日志 D:\FactorOS_Data\logs\ssh_watchdog.log     │
│                                                      │
│  Review mode:                                        │
│    scripts/ssh-health-check.ps1 → PASS/FAIL 审计     │
└──────────────────────────────────────────────────────┘
```

### 为何选这条路

| 方案 | 结论 |
|------|------|
| **SSH + 双侧 keepalive + 服务恢复 + 端口 watchdog** | **采用。** Cursor 兼容；覆盖空闲 NAT/防火墙踢人、sshd 挂死、服务未起。 |
| autossh / NSSM 隧道（Windows 当客户端） | **不适用。** 本场景是 Mac→Win 入站；autossh 解决的是出站隧道保活。 |
| mosh | **拒绝用于 Cursor。** 漫游更强，但 Remote-SSH 不走 mosh；可另开终端用，不替代 IDE。 |
| Tailscale / Cursor Tunnels | **可选增强**（跨网/换 IP），非本局域网刚需；不替代本机 sshd 硬化。 |
| 仅改一次 ClientAliveInterval | **不足。** 无服务恢复与端口自检时，sshd 死后仍需人工。 |

**Self-heal 边界：** Watchdog 恢复的是 **Windows 上的 sshd 监听**，不能复活已经死掉的那条 TCP。Mac/Cursor 仍需重连（或依赖扩展重连）；但目标是“一重连就能立刻通”，而不是“卡死几小时”。

---

## 3. 坑点表（他人踩过 → 我们如何规避）

| 坑 | 常见错误做法 | 我们的规避 |
|----|--------------|------------|
| 把 `ClientAlive*` 当成“踢空闲用户” | 按硬化指南设很短 Interval + CountMax=0 想强制登出 | 用作 **心跳保活**；`Interval 30` + `CountMax 5`（约 150s 无响应才断） |
| 只配服务端、Mac 不配 `ServerAlive*` | 中间 NAT/家用路由清闲置会话 | **Mac 永久**写 `ServerAliveInterval 30` |
| 依赖 `TCPKeepAlive`  alone | OS 默认探测间隔可达 ~2h，挡不住 NAT | 以 **应用层 Alive** 为主，TCPKeepAlive 保留 yes |
| Realtek / Windows 网卡节能 | “允许计算机关闭此设备以节约电源”→ 链路闪断 | 已禁用；健康检查持续审计 |
| AC 睡眠 / 混合睡眠 | 空闲后机器睡死，SSH 全断 | `STANDBYIDLE=0`；健康检查验电源方案 |
| sshd 服务挂了无人重启 | 只设 Automatic，无 Failure recovery / 无端口探活 | 服务失败重启 **+** 1–2 分钟端口 watchdog |
| 用 mosh 修 Cursor 掉线 | 装 mosh 仍无法给 Remote-SSH 用 | 文档明确：**Cursor = SSH only** |
| DHCP / 跨子网 IP 变化 | HostName 写死旧 IP；换 Wi‑Fi 后连错机 | Win 尽量静态/保留 `192.168.1.114`；Mac Host 用稳定 IP 或日后 mDNS/Tailscale |
| 双 NIC / VPN 抢默认路由 | SSH 通一阵后因出站路径变而断 | 家用有线主链路；避免 Win 全局 VPN 劫持；见 NETWORK_FIX.md |
| 乱改 `MaxStartups` / `LoginGraceTime` | 误以为能防掉线；过严导致新连接被拒 | **保持默认**；仅在暴力扫端口/半开连接打满时再调 |
| Match 块覆盖全局 keepalive | 后置 Match 改写 AuthorizedKeys 时误带冲突项 | 仅保留 `Match Group administrators` 的密钥路径；Alive 放全局 |
| 巨型一次性 `tar`/`scp` 拖死 sshd | 历史 broken pipe / sshd 异常 | 大文件 **分块**；与稳定性方案正交 |
| ControlMaster 僵死 socket | 多路复用坏了导致新会话挂起 | 可选启用；出问题删 `~/.ssh/cm-*`；健康文档注明 |
| 把空闲关机 watchdog 当 SSH 保活 | `FactorOS_IdleWatchdog` 会关机 | 分开任务名；SSH 任务只启停 sshd |

---

## 4. Windows 清单（永久）

| 项 | 期望值 | 落地 |
|----|--------|------|
| `sshd_config` | `TCPKeepAlive yes`；`ClientAliveInterval 30`；`ClientAliveCountMax 5` | `%ProgramData%\ssh\sshd_config` |
| Match | 无冲突 Alive 覆盖；Administrators 用 `administrators_authorized_keys` | 保留现有 Match |
| 服务 | `sshd` StartType=Automatic；失败 → 重启 | `sc.exe failure` |
| 电源 AC | 睡眠 / 休眠 = Never（0） | powercfg |
| NIC | `AllowComputerToTurnOffDevice = Disabled` | NetAdapterPowerManagement |
| 防火墙 | OpenSSH 入站 Allow | 现有 FactorOS / Preview 规则 |
| Watchdog | 计划任务 `FactorOS_SSHWatchdog` 每 1–2 分钟 | `scripts\install-ssh-watchdog.ps1` |
| 日志 | `D:\FactorOS_Data\logs\ssh_watchdog.log` | watchdog 写入 |
| Review | `scripts\ssh-health-check.ps1` | PASS/FAIL |

---

## 5. Mac 清单（一次性永久配置 — 必须在 Mac 上改）

在 **Mac** 编辑 `~/.ssh/config`，合并到现有 `Host factoros-win`（不要只跑一次命令行 `-o`）：

```sshconfig
Host factoros-win
    HostName 192.168.1.114
    User Administrator
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
    ServerAliveInterval 30
    ServerAliveCountMax 5
    TCPKeepAlive yes
    # 可选：多路复用，减少 Cursor/终端重复握手（出问题则注释掉并删 socket）
    # ControlMaster auto
    # ControlPath ~/.ssh/cm-%r@%h:%p
    # ControlPersist 10m
```

验证：

```bash
ssh -G factoros-win | egrep 'serveraliveinterval|serveralivecountmax|tcpkeepalive'
# 期望：serveraliveinterval 30 / serveralivecountmax 5 / tcpkeepalive true
```

Cursor：使用 **Remote-SSH**（`anysphere.remote-ssh`）连 `factoros-win`；**不要**换成 mosh。可选设置 `remote.SSH.connectTimeout` ≥ 60（慢链路握手）。

---

## 6. Self-heal（Windows）

| 组件 | 路径 / 名称 |
|------|-------------|
| 脚本 | 仓库 `scripts\ssh-watchdog.ps1`；运行副本 `C:\FactorOS\ssh\ssh-watchdog.ps1` |
| 安装 | `scripts\install-ssh-watchdog.ps1`（需管理员） |
| 任务 | `FactorOS_SSHWatchdog`，SYSTEM，最高权限，无论是否登录，每 **2 分钟** |
| 逻辑 | 若 `sshd` 非 Running **或** TCP 22 无 Listen → `Start-Service sshd`；追加日志 |
| 日志 | `D:\FactorOS_Data\logs\ssh_watchdog.log` |

与 `FactorOS_IdleWatchdog`（空闲关机）独立；勿合并。

---

## 7. Review / 审计模式

```powershell
cd C:\Users\Administrator\Projects\factoros-windows-node
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\ssh-health-check.ps1
```

输出每项 **PASS/FAIL**（sshd_config、服务、失败恢复、端口 22、电源、NIC、计划任务、防火墙、日志目录）。退出码：全 PASS → 0，否则 → 1。

---

## 8. 如何验证

1. **空闲保活：** Mac `ssh factoros-win` 后空闲 ≥30 分钟，会话仍在；或 Cursor Remote 保持连接。
2. **Watchdog：** 管理员 PowerShell：`Stop-Service sshd`；等待 ≤2 分钟；确认端口 22 再次 Listen，且日志有重启记录。
3. **审计：** 再跑 `ssh-health-check.ps1`，期望全 PASS。
4. **注意：** `Stop-Service` 会断现有会话；验证后在 Mac 侧重连即可。

---

## 9. 运维命令速查

```powershell
# 安装 / 刷新 SSH watchdog（管理员）
.\scripts\install-ssh-watchdog.ps1

# 审计
.\scripts\ssh-health-check.ps1

# 看自愈日志
Get-Content D:\FactorOS_Data\logs\ssh_watchdog.log -Tail 40

# 任务状态
Get-ScheduledTask -TaskName FactorOS_SSHWatchdog | Format-List TaskName, State
```

---

## 10. 参考（调研摘要）

- OpenSSH `ClientAlive*` / `ServerAlive*` 是 **无响应检测/心跳**，不是“空闲踢人”（ServerFault / Kickflop 澄清）。
- Windows OpenSSH 配置：`%ProgramData%\ssh\sshd_config`（Microsoft Learn）。
- Realtek/NIC 节能导致闪断：禁用 “Turn off this device to save power”。
- autossh+NSSM：适合 **出站隧道**，不是本场景的入站 sshd 保活。
- mosh：适合漫游终端；**Cursor Remote-SSH 不兼容**。
- DHCP/换 IP：TCP 会话定义上无法保活；需稳定 HostName 或 overlay VPN。
- `MaxStartups` 打满会导致 **新连接被拒**（像掉线），与已建立会话空闲无关；勿当 keepalive 调。
