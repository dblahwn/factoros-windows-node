# FactorOS Windows Node — 共享进度

双端对齐用。只写事实，不写密码。分工见 [WORK_SPLIT.md](./WORK_SPLIT.md)。

**当前状态：** HEADLESS_WORKER_READY + **WOL_SELFTEST_PASS** + **COLD_MIGRATE_COPY_DONE**（Mac 原件未删）+ **WATCHDOG_USERSAFE_DEPLOYED**（运行副本 SHA 已与本仓一致）+ **SSH_STABILITY**（keepalive + 端口 watchdog）

**更新时间：** 2026-08-09 11:30 CST（Mac agent 现场 SSH 复核后回写；唯一真相源：本文件，开工前先 `git pull`）

---

## 三方对齐（Mac agent / Windows Cursor / 用户）— 2026-08-09 11:30 CST

> 目标：先对齐「真问题」，再分工修。下面以 **Mac→`ssh factoros-win` 现场事实** 为准。
> **唯一真相源：** 本文件（`SHARED_STATUS.md`）+ GitHub `dblahwn/factoros-windows-node`；两边开工前先 `git pull origin main`。

### 现场快照（Mac agent ~11:30 CST）

| 项 | 结果 |
|---|---|
| `ssh factoros-win` | **OK** → `SSH_OK` / hostname `PC-202407291635` |
| Cursor on Win | **在跑**（多进程 `Cursor.exe`，Session Console #1） |
| `qwinsta` | `console` Administrator = **Active**；`rdp-tcp` = Listen（无 Active RDP） |
| `shutdown /a` | 无进行中关机（1116） |
| `shutdown_pending.json` | **不存在** |
| `CANCEL_SHUTDOWN.bat` | **存在**（`C:\FactorOS\jobs\`） |
| 桌面快捷方式 | **存在**「取消 FactorOS 关机.lnk」（用户桌面 + Public Desktop） |
| Idle Watchdog 任务 | `FactorOS_IdleWatchdog` **Enabled**；命令：`C:\FactorOS\jobs\watchdog.ps1`；上次约 11:27 Result=0；每 5 分钟 |
| Watchdog 脚本哈希 | Win SHA256=`0688b9ddade80d07eac283562c1be4b6b094e02fa5309dfdbe48dc44d207e4f5` **=** 本仓 `jobs/watchdog.ps1` |
| P0 引入 commit | `532a1e6` Fix idle watchdog…；对齐推送含 `6e46844`；当前 `origin/main` HEAD=`b9f5e32`（另含 SSH 稳定性） |
| Watchdog 日志今日 | 10:34–11:19 旧逻辑误杀 `IDLE -> shutdown /s /t 30`；**11:20 起** 新逻辑 stay on；11:26–11:27 `userApps`/`Active`/`cancel flag` → stay on |
| SSH 稳定性 | `FactorOS_SSHWatchdog` **已装**（约每 2 分钟）；详见 [SSH_STABILITY.md](./SSH_STABILITY.md) |

### 角色现状

| 角色 | 状态 / 期望 |
|---|---|
| **Mac agent** | 已 `git pull` 至 `b9f5e32`；SSH 现场复核完成；本文件回写并 push；继续用 SSH 做电源/连通/日志，Cloud 重活仍走 `compshare-gpu` |
| **Windows Cursor** | **预期在跑且可工作**；请 `git pull` 后对照本表核对 `C:\FactorOS\jobs` 与仓库一致，冒烟「取消关机」，可选跑 `scripts\ssh-health-check.ps1`，有差异则回写本文件 |
| **用户** | RDP 用 Mac「Windows App」；需时长开时 `mac/win_ctl.sh keepalive`；冷数据 purge 需显式确认 |

### 开放项（按优先级）

1. **P0 — 空闲看门狗误杀 → 已部署且仓内已对齐**  
   - 真因（已修）：旧逻辑不认 Active / 用户进程 / Cursor。  
   - 现状：**DEPLOYED**；Win 运行副本 SHA = 本仓；任务指向 `C:\FactorOS\jobs\watchdog.ps1`。  
   - 剩余：Windows Cursor **本机 UI 冒烟**（询问弹窗「否」/ 桌面取消快捷方式 / `CANCEL_SHUTDOWN.bat` / `shutdown /a`）；确认后回写「P0 冒烟 PASS」。

2. **P1 — SSH 间歇无 banner → 当前 OK + 自愈已落地**  
   - 现场：`ssh factoros-win` **OK**。  
   - 已落地：sshd ClientAlive*、`FactorOS_SSHWatchdog`、健康检查脚本（见 SSH_STABILITY.md）。  
   - 剩余：失败时记时间 + Event Viewer/sshd；Mac 侧永久加 `ServerAliveInterval 30`（若尚未）。

3. **P2 — 双网段 ping 噪音**（预期，非主故障；勿用 ping 当健康检查）。

4. **P3 — 无头体验**：依赖 Windows App RDP；此刻 console Active。

5. **P4 — Bluetooth「cc jbl」**：便利项，Win 本机配对。

6. **P5 — Mac 盘紧**：冷 copy **done / bad=0**；**未 purge**（需用户确认）。

### 已经修好 / 可用

- WOL 自检 **PASS**；`mac/win_ctl.sh` wake/wait-up/keepalive/submit  
- 冷迁移 copy → `D:\FactorOS_Data`（Mac 原件保留）  
- Headless jobs：`D:\FactorOS_Data\jobs\{inbox,running,outbox,failed}`  
- Idle watchdog **用户安全版运行中**（自 ~11:20）；无 pending 关机  
- Cursor **Windows 本机运行中**  
- **SSH_STABILITY** 已进仓并装任务（HEAD `b9f5e32`）

### 分工：谁做什么

| 角色 | 现在做 | 不要做 |
|---|---|---|
| **Mac agent** | 维护本文件真相；SSH 复核电源/连通/日志；编排 Cloud 重活；Mac `~/.ssh/config` 按 SSH_STABILITY 加 ServerAlive* | 勿再改 Desktop iCloud 鬼目录；勿用 ping 判死 |
| **Windows Cursor** | `git pull` → 读「三方对齐」；核对 `C:\FactorOS\jobs`；UI 冒烟取消通道；SSH 再挂时查本机日志并回写 | 勿把 Mac 编排仓当 Win 唯一源；勿把 fleet/LLM 重活塞进 Win |
| **用户** | Windows App RDP；`keepalive` 保活；确认后再 purge | 勿两边互覆盖未 pull 的同一文件 |

### Windows Cursor 最小动作清单

1. `cd` 到本仓检出 → `git pull origin main`（应对齐到含 `b9f5e32` / 至少含 `532a1e6`+`6e46844`）  
2. 打开本文件，以本节为准，回写确认时间戳  
3. 核对计划任务仍指向 `C:\FactorOS\jobs\watchdog.ps1`；必要时管理员跑 `jobs\install_watchdog.ps1`  
4. 冒烟：桌面「取消 FactorOS 关机」/`CANCEL_SHUTDOWN.bat`/`shutdown /a`  
5. 可选：`powershell -File .\scripts\ssh-health-check.ps1`（期望 ALL PASS）  
6. SSH 再失败：记下时间 → 事件/sshd → 回写 P1

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
