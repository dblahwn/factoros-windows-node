# FactorOS Windows Node — 共享进度

双端对齐用。只写事实，不写密码。分工见 [WORK_SPLIT.md](./WORK_SPLIT.md)。

**当前状态：** HEADLESS_WORKER_READY + **WOL_SELFTEST_PASS** + **COLD_MIGRATE_COPY_DONE**（Mac 原件未删）+ **WATCHDOG_USERSAFE_DEPLOYED** + **SSH_STABILITY**（keepalive + 端口 watchdog，健康检查 ALL PASS）

**更新时间：** 2026-08-09 11:30 CST（Mac agent 现场复核；Win 侧 SSH 稳定性落地同日）

---

## 三方对齐（Mac agent / Windows Cursor / 用户）— 2026-08-09 11:30

> 目标：先对齐「真问题」，再分工修。下面以 **Mac→SSH 现场事实** 为准。

### 现场快照（刚才）

| 项 | 结果 |
|---|---|
| `ssh factoros-win` | **OK** → `PC-202407291635` / `pc-202407291635\administrator` |
| Cursor on Win | **在跑**（多进程 `Cursor.exe`，Session Console #1） |
| `qwinsta` | `console Administrator` = **Active**；`rdp-tcp` = Listen（当前无 Active RDP） |
| `shutdown /a` | 无进行中关机（1116） |
| `shutdown_pending.json` | **不存在** |
| Watchdog 任务 | `FactorOS_IdleWatchdog` Enabled；跑 `C:\FactorOS\jobs\watchdog.ps1`；上次 11:24 Result=0 |
| Watchdog 日志今日 | 10:34–11:19 仍按旧逻辑 `IDLE -> shutdown /s /t 30`（误判）；**11:20 起** 已是新逻辑：`user present (Active session) -> stay on` |
| 部署哈希 | Win `C:\FactorOS\jobs\watchdog.ps1` SHA256=`0688b9dd…` **= Mac 工作区未提交版**；GitHub `origin/main` 上的 `86e684b` 仍是上一版（无 UserApps / CANCEL bat 完善） |
| SSH 稳定性 | `FactorOS_SSHWatchdog` 已装（每 2 分钟）；`ClientAliveInterval 30` / `CountMax 5`；`ssh-health-check.ps1` **ALL PASS**；模拟 Stop-Service 后 watchdog 已恢复监听 |

### 现在坏什么（按优先级）

1. **P0 — 空闲看门狗曾误杀，且 GitHub ≠ 机上运行副本**  
   - 真因：旧逻辑只看 jobs/keepalive/`last_activity`，**不认 Active 会话 / 用户在打字 / Cursor**；`last_activity` 卡在 08-06，导致开机后反复 `shutdown /t 30`。  
   - 现状：机上 **已热部署** 新脚本（Active 会话 + 用户进程 + 先询问 + 1h 无应答再关 + 取消通道）。  
   - 缺口：改动还在 Mac 工作区 / Win `C:\FactorOS\jobs`，**未完整进 GitHub** → Windows Cursor `git pull` 会拿到旧于运行中的代码。  
   - 验收：空闲判定前必须看到 Active/`user apps`/`keepalive` 任一则 stay on；询问弹窗「否」或 `CANCEL_SHUTDOWN.bat` / `shutdown /a` 必能取消。

2. **P1 — SSH 间歇 `kex_exchange_identification: Connection closed by remote host`（无 banner）**  
   - 真因候选：sshd 未就绪 / 连接风暴 / 关机或休眠边缘 / MaxStartups。  
   - **不是**「双网段 ping 不通」本身（见下）。  
   - 现状：此刻 SSH **可用**；已落地 **永久保活 + 端口自愈**（见 [SSH_STABILITY.md](./SSH_STABILITY.md)）。失败时仍抓 Win 事件/sshd 日志。  
   - Mac 侧须一次性永久加 `ServerAliveInterval 30`（文档内片段）。

3. **P2 — 双网段拓扑噪音（Mac `192.168.13.105` Wi‑Fi / Win `192.168.1.114` 有线）**  
   - ICMP ping 常失败、TCP/SSH/RDP 可通 → **预期行为，不是主故障**。  
   - 连通性以 `ssh factoros-win` / Windows App RDP 为准，不要用 ping 当健康检查。

4. **P3 — 无头使用体验**  
   - 依赖 Mac「Windows App」RDP；此刻会话在 **console Active**（可能是本机登录/自动登录，不一定是 RDP）。  
   - 文档：`mac/RDP_FROM_MAC.md`。

5. **P4 — Bluetooth「cc jbl」**  
   - 便利项，不阻塞算力/数据。Win Cursor 本地配对即可。

6. **P5 — Mac 盘仍紧**  
   - 冷数据 **copy 已完成**（bad=0）；**未 purge**。腾盘需用户确认后再删（见下文列表）。

### 已经修好 / 可用

- WOL 自检 **PASS**；`mac/win_ctl.sh` wake/wait-up/keepalive/submit  
- 冷迁移 copy：llm_rft_pilot / archive / cache / reports / `astock_18y.db` 等 → `D:\FactorOS_Data`（Mac 原件保留）  
- Headless jobs 目录：`D:\FactorOS_Data\jobs\{inbox,running,outbox,failed}`  
- Watchdog **用户安全版已在 Win 运行**（自 ~11:20）：认 Active；stay on；无 pending 关机  
- Cursor **已在 Windows 本机运行**（可与 Mac agent 分读写）  
- **SSH_STABILITY**：sshd keepalive、服务失败重启、`FactorOS_SSHWatchdog`、审计脚本；详见 [SSH_STABILITY.md](./SSH_STABILITY.md)

### 分工：谁做什么

| 角色 | 现在做 | 不要做 |
|---|---|---|
| **Mac agent** | 推送本仓（SHARED_STATUS + jobs 看门狗与运行副本一致）；用 SSH 做电源/连通/日志复核；编排 Cloud 重活；**应用 SSH_STABILITY.md 中 Mac `~/.ssh/config` 永久片段** | 勿再改 Desktop iCloud 鬼目录；勿用 ping 判死 |
| **Windows Cursor** | `git pull` 本仓读本文件；**核对** `C:\FactorOS\jobs` 与仓库一致（或按 `install_watchdog.ps1` 重装任务）；用本机 UI 验「询问/取消」；可选配对 Bluetooth；本机看 Event Viewer / sshd 当 SSH 再挂；SSH 审计：`.\scripts\ssh-health-check.ps1` | 勿改 Mac 编排真相仓当唯一源；勿把 fleet/LLM 重活塞进 Win |
| **用户** | Mac 用 Windows App 连 RDP；需要时长开时 `win_ctl.sh keepalive`；确认后再 purge 冷数据；Mac 侧写死 ServerAlive* | 勿同时让两边互相覆盖同一未提交文件而不 pull |

### Windows Cursor 最小动作清单

1. `cd` 到 `factoros-windows-node` 检出（若在 `D:\dev\…` 或 `C:\FactorOS` 旁路 clone）→ `git pull`  
2. 打开本文件，以 **「三方对齐」** 为准  
3. 确认计划任务仍指向更新后的 `C:\FactorOS\jobs\watchdog.ps1`；必要时管理员跑 `jobs\install_watchdog.ps1`  
4. 桌面应有「取消 FactorOS 关机」；手动点一次取消路径做冒烟  
5. SSH 再失败时：记下时间，查 sshd/事件日志，回写本文件「P1」小节  
6. 复核 SSH 稳定性：`.\scripts\ssh-health-check.ps1`（期望 ALL PASS）

---

## 电源 / 无头作业（已通 + 看门狗加固中）

| 项 | 值 |
|---|---|
| SSH | `ssh factoros-win` OK；稳定性方案见 [SSH_STABILITY.md](./SSH_STABILITY.md)（仍可能有间歇无 banner，自愈后重连即可） |
| SSH 保活 | `ClientAliveInterval 30` / `CountMax 5`；`TCPKeepAlive yes` |
| SSH 自愈 | 计划任务 `FactorOS_SSHWatchdog` 每 2 分钟；日志 `D:\FactorOS_Data\logs\ssh_watchdog.log` |
| SSH 审计 | `scripts\ssh-health-check.ps1`（PASS/FAIL review mode） |
| WOL | NIC `WakeOnMagicPacket=Enabled`；自检 `mac/wol_selftest.sh` **PASS** |
| 空闲关机 | `FactorOS_IdleWatchdog` 每 5 分钟；**有 Active 会话 / 用户程序 / jobs / keepalive → 不开机关**；仅真正空闲 ≥2h → **询问**；1h 无应答再关；取消：弹窗「否」/`shutdown /a`/`CANCEL_SHUTDOWN.bat`/keepalive |
| Mac 控制 | `mac/win_ctl.sh`（wake/wait-up/shutdown/keepalive/submit/fetch） |
| 自动复检 | LaunchAgent `com.factoros.wol-selftest`（周检） |
| 作业目录 | `D:\FactorOS_Data\jobs\{inbox,running,outbox,failed}` |
| 脚本部署 | 运行副本：`C:\FactorOS\jobs\`（任务指向此处）；SSH watchdog：`C:\FactorOS\ssh\` |

## 冷数据迁移（copy 完成，Mac 未 purge）

脚本：`mac/migrate_cold_data_to_win.sh` → `D:/FactorOS_Data`（正斜杠；chunked `dd|ssh|python`；size 匹配则 SKIP）。日志：`factor_os/backtest_results/migrate_cold_to_win.log`。

| 源（Mac） | 目的（Win） | 状态 | 核对 |
|---|---|---|---|
| `factor_os/backtest_results/llm_rft_pilot`（116 files） | `D:/FactorOS_Data/backtest_results/llm_rft_pilot` | OK | 含 extract.gz 970306405、slim.gz 317035120、`grpo_ckpt/final/model.safetensors` 3087467144；Win 另留 `_small_files.tar` |
| `factor_os/backtest_results/port_value_q_001_protocol_r`（9 / ~122M） | `.../port_value_q_001_protocol_r` | OK | 127768545 bytes |
| `factor_os/archive`（177 / ~65M） | `D:/FactorOS_Data/archive/factor_os_archive` | OK | 67910886 bytes |
| `factor_os/cache`（8 / ~856M） | `D:/FactorOS_Data/cache/factor_os_cache` | OK | 896292605 bytes（含 control_panel + LLM_RFT_* + fwd_ret） |
| `data/reports`（4 / ~4M） | `D:/FactorOS_Data/reports` | OK | 4140932 bytes |
| `data/astock_18y.db`（~10.1G） | `D:/FactorOS_Data/data/astock_18y.db` | OK | **10862878720** 双边一致；**Mac 原件保留** |

全量抽查：Mac 侧 314 个冷文件 vs Win **bad=0**（2026-08-06 14:56 CST）。Win `D:` 剩余约 **132.5 GB**。

**建议 purge（需人工确认后再删，勿自动 PURGE=1）：**
1. `factor_os/backtest_results/llm_rft_pilot`（~4.1G）
2. `factor_os/backtest_results/port_value_q_001_protocol_r`（~122M）
3. `factor_os/archive`（~65M）
4. `factor_os/cache`（~856M）
5. （可选）`data/reports`（~4M）— 若确认只在 Win 用
6. **不要删** `data/astock_18y.db`（除非另有备份策略；已有 Win 副本但仍作 Mac 主库）

预计可腾出约 **~5.1G**（不含 astock）。重活仍走 `compshare-gpu`。

## 路径速查

| 用途 | 路径 |
|---|---|
| Win 代码 | `D:\dev\FactorOS` |
| Win 节点仓 / 作业脚本源 | GitHub `dblahwn/factoros-windows-node`；运行副本常在 `C:\FactorOS\jobs` |
| Win 数据 | `D:\FactorOS_Data` |
| Mac 编排 | `~/dev/FactorOS` + `factoros_windows_node/mac/win_ctl.sh` |
| Cloud | `Host compshare-gpu` |
