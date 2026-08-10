# FactorOS Windows Node — 共享进度

双端对齐用。只写事实，不写密码。分工见 [WORK_SPLIT.md](./WORK_SPLIT.md)。

**当前状态：** HEADLESS_WORKER_READY + WOL_SELFTEST_PASS + COLD_MIGRATE_COPY_DONE + SSH_STABILITY + SOFT_CFG_PASS + **WATCHDOG_OVERNIGHT_FIX_IN_REPO**（待下次开机部署）

**更新时间：** 2026-08-10 09:55 CST（Mac agent：过夜未关机根因已修于仓；部署因本机 SSH/关机窗口未完成）

---

## P0 — 过夜空闲未关机（2026-08-10）

> 用户澄清：「看门狗没用」= **整夜空闲不自动关**，不是误杀。

### 根因（代码级，旧 usersafe 版）

1. `Test-UserAppsBusy` 把 SessionId>0 有主窗口的进程（含 **Cursor**）当成 forever-busy  
2. 每次 tick 若 busy → `Touch-Activity` → `last_activity` 每 5 分钟刷新 → **idle 永远到不了 2h**  
3. 控制台名义 Active / ghost session 也会走同一条 stay-on 路径  
4. 结果：人已离开、无 RDP、无 jobs，机器仍整晚开着

### 新逻辑（仓内已改，见 `jobs/watchdog.ps1`）

| 保活（阻止询问/关机） | 不保活（过夜应能关） |
|---|---|
| 活跃 RDP（`rdp-tcp#N` Active；忽略 Listen） | 仅残留 Cursor/explorer 等后台进程 |
| `quser` IDLE TIME &lt; 2h（近期键鼠） | 控制台 Active 但输入空闲 ≥2h |
| inbox/running / keepalive&lt;2h / cancel | 旧「有用户程序就 Touch-Activity」已删除 |

流程仍是：**空闲 ≥2h → 询问（`/t 3600`）→ 1h 无应答 → 强制关**。无头无人点弹窗也会在 ask 超时后关。

### 下次开机必须部署（Mac 或 Win Cursor）

```powershell
# 在 Win 上（elevated），从节点仓 jobs 安装运行副本 + 任务
cd D:\dev\factoros-windows-node   # 或先 git pull / 从 Mac scp
powershell -NoProfile -ExecutionPolicy Bypass -File .\jobs\install_watchdog.ps1
# install 会：复制到 C:\FactorOS\jobs\、重装 FactorOS_IdleWatchdog(SYSTEM/5min)、
# 重置 watchdog_state last_activity 为 -3h（避免旧 inflated 状态）
```

Mac 若 SSH 可用：

```bash
scp factoros_windows_node/jobs/{watchdog.ps1,ask_shutdown.ps1,CANCEL_SHUTDOWN.bat,install_watchdog.ps1} factoros-win:'C:/FactorOS/jobs/'
ssh factoros-win 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\FactorOS\jobs\install_watchdog.ps1'
```

验收：无 RDP + 无 keepalive + 无 jobs 时，日志应出现 `no_recent_presence` / `session input idle … ignore last_activity`，而不是 `userApps busy … Cursor`。

### 电源（本轮 Mac 侧）

- 2026-08-10 ~09:49：曾短暂 SSH UP，随后对 `192.168.1.114` ping 丢、SSH 在 kex 被对端关闭（疑似并行关机/sshd 半死）  
- TCP 22/3389 仍曾短暂可连但无 banner → **未能热部署**；以本文件 + 仓内脚本为准，**下次 boot 先 deploy 再干活**

---

## 软件配置 checklist（Mac agent SSH @ 2026-08-09 ~11:43–11:45 CST）

> 目标：headless worker + 日常 RDP/Cursor，不装无关软件。报告：`D:\FactorOS_Data\logs\soft_cfg_report.json`

| 项 | 结果 | 备注 |
|---|---|---|
| Python 3.12 | **OK** | `C:\Program Files\Python312\python.exe` 3.12.8 |
| Git | **OK** | 2.55.0；Machine PATH 已含 `Git\bin` + `Git\cmd` |
| Cursor | **OK** | `...\Local\Programs\cursor\Cursor.exe` |
| OpenSSH / sshd | **OK** | 客户端在 PATH；`sshd` **Running + Automatic**；failure restart 已设 |
| Edge | **OK** | 已装；**未**另装 Chrome |
| winget | **INFO** | 不在 PATH（应用已齐，未强装 App Installer） |
| `FactorOS_IdleWatchdog` | **OK** | Ready；已从 `D:\dev\factoros-windows-node\jobs` 重装部署 |
| `FactorOS_SSHWatchdog` | **OK** | Ready；已从 `...\scripts` 重装部署 |
| `D:\dev\FactorOS\.venv` | **OK** | `import pandas` → 3.0.5 |
| 电源（插电） | **OK** | 睡眠=从不、休眠=关、显示器=15 分钟；`hibernate off` |
| 唤醒需登录 | **OK** | `CONSOLELOCK=0`（插电唤醒少摩擦；锁屏策略仍可能存在） |
| 时区 / 对时 | **OK** | `China Standard Time`；W32Time resync |
| RDP | **OK** | `fDenyTSConnections=0`；防火墙 Remote Desktop 组已启用 |
| 节点仓检出 | **OK** | `D:\dev\factoros-windows-node` @ `c6b90c9`（Win Cursor 用） |
| keepalive | **OK** | 已 touch（softcfg + `win_ctl.sh keepalive`） |
| Bluetooth「cc jbl」 | **NEED 用户** | BT 服务已 Automatic+Running；**PnP 无 Bluetooth 适配器/设备**（0 radios）→ 需插 USB BT 或 BIOS 开蓝牙后，RDP 进「设置 → 蓝牙」首次配对 |

未做：改装浏览器/游戏、改密码、关机。

---

## 三方对齐（Mac agent / Windows Cursor / 用户）— 2026-08-09 11:45 CST（叠 11:37 冒烟）

> 目标：先对齐「真问题」，再分工修。Mac→`ssh factoros-win` 快照仍有效；**取消通道验收以本机 Windows Cursor 为准**。
> **唯一真相源：** 本文件（`SHARED_STATUS.md`）+ GitHub `dblahwn/factoros-windows-node`；两边开工前先 `git pull origin main`。

### 现场快照（Mac：SSH OK / 看门狗热更新 / 无 pending + Win Cursor 11:37 复验）

| 项 | 结果 |
|---|---|
| `ssh factoros-win` | **OK**（Mac 摘要）→ hostname `PC-202407291635`；本机 `sshd` Running，`:22` Listen |
| Cursor on Win | **在跑**（本会话即 Windows Cursor；Session Console #1） |
| `shutdown /a` | 冒烟后无进行中关机（1116） |
| `shutdown_pending.json` | **不存在**（`D:\FactorOS_Data\jobs\`） |
| `CANCEL_SHUTDOWN.bat` | **存在**（`C:\FactorOS\jobs\`） |
| 桌面快捷方式 | **存在**（User + Public Desktop → `C:\FactorOS\jobs\CANCEL_SHUTDOWN.bat`；文件名编码显示乱码，Target 正确） |
| Idle Watchdog 任务 | `FactorOS_IdleWatchdog` **Ready/Enabled**；命令：`C:\FactorOS\jobs\watchdog.ps1`；LastResult=0；每 **5** 分钟 |
| Watchdog 脚本 | 运行副本存在；`git hash-object` 与仓 **相同**（逻辑一致）；磁盘 SHA256 因 LF(run)/CRLF(repo) 不同：run=`0688b9dd…` / repo=`b858e33e…` — **非内容漂移** |
| SSH 稳定性 | `FactorOS_SSHWatchdog` **Ready/Enabled**；触发 **PT2M**；LastResult=0；脚本 `C:\FactorOS\ssh\ssh-watchdog.ps1`；`ssh-health-check.ps1` **ALL PASS (18)** |

### Windows Cursor 验收 — 取消关机路径（2026-08-09 11:36–11:37 CST 再冒烟）

方法：`shutdown /s /t 180` 武装短延时关机（**未真实断电**），再走取消；终态 `shutdown /a`=1116 且无 `shutdown_pending.json`。

| 路径 | 结果 | 说明 |
|---|---|---|
| `shutdown /a` | **PASS** | 取消后 `/a` → 1116（无 pending 定时器） |
| `CANCEL_SHUTDOWN.bat` | **PASS** | `/nopause`：清定时器 + 删 pending + 写 `shutdown_cancel.flag` + 刷新 `keepalive` |
| 桌面「取消 FactorOS 关机」 | **PASS** | User + Public Desktop 均指向 `C:\FactorOS\jobs\CANCEL_SHUTDOWN.bat` |
| 询问 →「否」 | **PASS*** | *未自动点 MessageBox；`ask_shutdown.ps1` 含 `Invoke-CancelShutdown`（DefaultButton=否）；等价路径（cancel flag + keepalive + `/a`）冒烟 PASS。完整 UI 人工点「否」仍可选 |

运行副本：认 Active / userApps（含 Cursor）/ keepalive / cancel flag → stay on；先询问再关。Mac：看门狗已热更新；无 pending 关机。

### 角色现状

| 角色 | 状态 / 期望 |
|---|---|
| **Mac agent** | SSH OK；**SOFT_CFG_PASS** 已回写；看门狗已重部署；无 pending；继续 SSH/Cloud；Mac `ServerAlive*` 已在 `~/.ssh/config` |
| **Windows Cursor** | ✅ `git pull`；✅ P0 IdleWatchdog + 取消四路径再冒烟 PASS；✅ P1 SSHWatchdog + health ALL PASS (18) 已回写 |
| **用户** | RDP 用 Mac「Windows App」；需时长开时 `mac/win_ctl.sh keepalive`；冷数据 purge 需显式确认；有空可再手动点一次询问「否」 |

### 开放项（按优先级）

1. **P0 — 空闲看门狗误杀 → 已部署 + 取消通道再冒烟 PASS**  
   - 真因（已修）：旧逻辑不认 Active / 用户进程 / Cursor。  
   - 现状：**DEPLOYED**；任务指向 `C:\FactorOS\jobs\watchdog.ps1`；与仓逻辑一致（仅行尾 LF/CRLF）。  
   - **Windows Cursor 本机复验（11:37）：** IdleWatchdog Ready/0；`shutdown /a` / `CANCEL_SHUTDOWN.bat` / 桌面快捷方式 / 询问「否」代码路径 → **全部 PASS**（未真实断电）。

2. **P1 — SSH 间歇无 banner → 当前 OK + 自愈已落地**  
   - 现场：Mac **SSH OK**；本机 `sshd` Running / `:22` Listen；`ssh-health-check.ps1` **ALL PASS (18)**。  
   - 已落地：sshd ClientAlive*、`FactorOS_SSHWatchdog`（每 ~2 分钟）、健康检查脚本（见 SSH_STABILITY.md）。  
   - **Windows Cursor（11:37）：** 任务 Enabled、LastResult=0、脚本存在。失败时记时间再回写。  
   - Mac 侧须永久加 `ServerAliveInterval 30`（若尚未）。

3. **P2 — 双网段 ping 噪音**（预期，非主故障；勿用 ping 当健康检查）。

4. **P3 — 无头体验**：依赖 Windows App RDP；此刻 console Active。

5. **P4 — Bluetooth「cc jbl」**：**服务侧已开**；**缺适配器硬件**（PnP 0 devices）。用户：确认机箱/主板蓝牙或插 USB 适配器 → RDP → 设置 → 蓝牙与设备 → 添加「cc jbl」/JBL。

6. **P5 — Mac 盘紧**：冷 copy **done / bad=0**；**未 purge**（需用户确认）。

7. **P6 — 软件配置**：**SOFT_CFG_PASS**（见上表）；Win 节点仓路径 `D:\dev\factoros-windows-node`。

### 已经修好 / 可用

- WOL 自检 **PASS**；`mac/win_ctl.sh` wake/wait-up/keepalive/submit  
- 冷迁移 copy → `D:\FactorOS_Data`（Mac 原件保留）  
- Headless jobs：`D:\FactorOS_Data\jobs\{inbox,running,outbox,failed}`  
- Idle watchdog **用户安全版运行中**（自 ~11:20；Mac 热更新确认）；无 pending 关机  
- **取消关机四路径本机再冒烟 PASS**（Windows Cursor 2026-08-09 11:37；未真实断电）  
- Cursor **Windows 本机运行中**  
- **SSH_STABILITY** 已进仓并装任务；健康检查 ALL PASS (18)  
- **软件配置 SOFT_CFG_PASS**（电源/时区/RDP/sshd/venv/watchdogs/节点仓检出）

### 分工：谁做什么

| 角色 | 现在做 | 不要做 |
|---|---|---|
| **Mac agent** | 维护本文件真相；SSH 复核电源/连通/日志；编排 Cloud 重活；Mac `~/.ssh/config` 按 SSH_STABILITY 加 ServerAlive* | 勿再改 Desktop iCloud 鬼目录；勿用 ping 判死 |
| **Windows Cursor** | ✅ P0/P1 再冒烟已回写；SSH 再挂时查本机日志并回写；可选 Bluetooth | 勿把 fleet/LLM 重活塞进 Win；勿在未对齐时覆盖运行副本（行尾差异勿当内容漂移重部署） |
| **用户** | Windows App RDP；`keepalive` 保活；确认后再 purge | 勿两边互覆盖未 pull 的同一文件 |

### Windows Cursor 最小动作清单

1. ✅ `git pull origin main`；以本节为准  
2. ✅ 计划任务指向 `C:\FactorOS\jobs\watchdog.ps1`（LastResult=0）；与仓逻辑一致（CRLF/LF only）  
3. ✅ 冒烟：桌面取消 / `CANCEL_SHUTDOWN.bat` / `shutdown /a` / 询问「否」代码路径 → PASS（11:37）  
4. ✅ `powershell -File .\scripts\ssh-health-check.ps1` → ALL PASS (18)；`FactorOS_SSHWatchdog` PT2M Enabled  
5. SSH 再失败：记下时间 → 事件/sshd → 回写 P1  
6. （可选）人工点一次询问弹窗「否」做完整 UI 冒烟；可选修复桌面快捷方式文件名编码显示

---

## 电源 / 无头作业（已通 + 看门狗加固中）

| 项 | 值 |
|---|---|
| SSH | `ssh factoros-win` OK；稳定性方案见 [SSH_STABILITY.md](./SSH_STABILITY.md)（仍可能有间歇无 banner，自愈后重连即可） |
| SSH 保活 | `ClientAliveInterval 30` / `CountMax 5`；`TCPKeepAlive yes` |
| SSH 自愈 | 计划任务 `FactorOS_SSHWatchdog` 每 2 分钟；日志 `D:\FactorOS_Data\logs\ssh_watchdog.log` |
| SSH 审计 | `scripts\ssh-health-check.ps1`（PASS/FAIL review mode） |
| WOL | NIC `WakeOnMagicPacket=Enabled`；自检 `mac/wol_selftest.sh` **PASS** |
| 空闲关机 | `FactorOS_IdleWatchdog` 每 5 分钟；**活跃 RDP / 近期键鼠 / jobs / keepalive → 不开机关**；残留 Cursor 不挡；空闲 ≥2h → **询问**；1h 无应答再关。**2026-08-10 过夜修复在仓，待 boot 部署** |
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
| Win 节点仓 / 作业脚本源 | 检出 `D:\dev\factoros-windows-node`（GitHub `dblahwn/factoros-windows-node`）；运行副本 `C:\FactorOS\jobs` + `C:\FactorOS\ssh` |
| Win 数据 | `D:\FactorOS_Data` |
| Mac 编排 | `~/dev/FactorOS` + `factoros_windows_node/mac/win_ctl.sh` |
| Cloud | `Host compshare-gpu` |
