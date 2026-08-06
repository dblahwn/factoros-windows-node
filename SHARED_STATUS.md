# FactorOS Windows Node — 共享进度

双端 Cursor（Mac / Windows）对齐用；算力另见 Cloud。只写事实，不写密码。

分工见 [WORK_SPLIT.md](./WORK_SPLIT.md)（**三机**：Mac 编排 · Windows 磁盘 · Cloud 算力）。

## 双方 Agent 使用规则

1. 阶段变化时更新本文件顶部「当前状态」一行。
2. 动手前先 `git pull`，改完后 `git push` 到本仓库 `main`。
3. 只写可复述的事实；禁止写入密码、token、私钥等密钥。

---

**当前状态：** HEADLESS_WORKER_READY — inbox/outbox + 2h idle watchdog + Mac win_ctl (WOL/shutdown)

**更新时间：** 2026-08-06 ~13:00 CST

## 网络与访问

| 项 | 值 |
|---|---|
| Mac | **192.168.13.105**（Wi‑Fi / en0；网关 192.168.13.1）— IP **未变**，非过期 |
| Windows | 192.168.1.114（主机名 PC-202407291635） |
| Cloud | `Host compshare-gpu`（Mac `~/.ssh/config` → cpod…compshare.cn）— **重算力** |
| 双网段 | Mac `192.168.13.x` ↔ Win `192.168.1.x`（跨子网路由可达；见下） |
| SSH | **PASS** — `ssh factoros-win` 与 `ssh Administrator@192.168.1.114`：`whoami`→`pc-202407291635\administrator`，`SSH_OK` |
| SMB | **PASS** — `/Volumes/FactorOS_Data` 已挂载；Win `D:\FactorOS_Data` ↔ Mac 卷双向读写测通（2026-08-06） |
| RDP | **PASS（端口）** — `nc -z -G 3 192.168.1.114 3389` 成功（未做完整登录） |
| Win→Mac ping | **FAIL（预期）** — `ping -n 2 192.168.13.105` 100% 超时；跨子网 + Mac/防火墙挡 ICMP，**不表示** SSH/SMB 坏 |

## Windows 机器（存储节点，非主力算力）

| 项 | 值 |
|---|---|
| 角色 | **磁盘 + 轻/中量脚本**；勿迁全部重型回测到此机 |
| CPU | i7-7700（偏弱） |
| 内存 | 16GB RAM |
| GPU | 无独立显卡 |
| 磁盘 | C≈90GB 空闲；D≈139GB 空闲；E≈390GB；F≈317GB |
| Python | 3.12.8 **OK**（系统）；`D:\dev\FactorOS\.venv` **OK**（pandas 3.0.5 / numpy 2.5.1 / pyarrow 25.0.0） |
| Git | 2.55 |

## 路径与仓库

| 项 | 值 |
|---|---|
| 代码仓（Win） | `D:\dev\FactorOS`；git HEAD `629654d` on `main`（与 Mac/GitHub 一致） |
| 数据盘（Win） | `D:\FactorOS_Data` — `cache/`、`backtest_results/`、`data/` + `README_SLIM.txt`；**勿 clone 代码进此目录** |
| Mac 代码 | `~/dev/FactorOS`（轻量编辑；避免复制大体量 data） |
| 瘦拷贝 | **SKIPPED** `data/`（~10G）、`backtest_results/`（~7G）、`archive/` — 大数放 SMB `D:\FactorOS_Data`；重活上 **compshare-gpu** |

## 账号与策略（无密码）

- Administrator **已设置密码**（本文不写密码）。
- `LimitBlankPasswordUse` 已设为 `0`。

## 已知问题

- Windows 上 HTTPS `git clone` 私有仓失败（GCM）；优先用 **Mac→Windows SSH 拷贝**。
- Win 无法 ping 通 Mac **属预期**；以 Mac→Win SSH/SMB 为准，勿用反向 ping 判死活。
- `D:\dev\FactorOS` 工作树 **dirty**（~500 路径：多为 `archive/` / `paper_trading_logs/` 删除 + 少量修改；HEAD 仍为 `629654d`）。不阻塞 READY；勿随意 `git reset`/`commit` 除非双端对齐后处理。
- 家用 Win **性能差**：大 fleet / 全历史 / LLM·RFT → Cloud，不要默认堆到 Win。

## 下一步清单

- [x] SSH `factoros-win` 可用（Mac 复核 2026-08-06）
- [x] `D:\dev\FactorOS` 就位且 HEAD 对齐 Mac/GitHub（`629654d`）
- [x] 瘦拷贝策略确认（跳过大目录）
- [x] Python 3.12.8 + `.venv` 轻量依赖（pandas/numpy/pyarrow）
- [x] Mac SMB 挂载 `FactorOS_Data` + 双向写测（Mac 复核）
- [x] `D:\FactorOS_Data\{cache,backtest_results,data}` 占位
- [x] RDP 3389 端口可达（可选；Mac `nc` 复核）
- [x] Mac Cursor Remote SSH → `factoros-win` → 打开 `D:\dev\FactorOS`（2026-08-06 ~11:33 CST 接通）
- [x] 三机分工文档 `WORK_SPLIT.md`（Mac / Win 磁盘 / Cloud 算力）
- [x] 无头作业 inbox/outbox + `FactorOS_IdleWatchdog`（空闲 2h 自动关机）
- [x] Mac `mac/win_ctl.sh`（wake/wait-up/shutdown/keepalive/submit/fetch）；WOL MAC=`E0:D5:5E:A3:CC:24`
- [ ] BIOS/网卡 **Wake-on-LAN** 实测（关机后 `win_ctl.sh wait-up`）；跨子网广播可能需路由放行

## Cursor Remote

- **根因（首次失败）**：Win PATH 无 `bash`（仅有 `Git\cmd`）；Remote-SSH 装 server 时报 `'bash' 不是内部或外部命令`。
- **修复**：已把 `C:\Program Files\Git\bin` 写入 Win **Machine PATH**；`ssh factoros-win bash --version` 现 **PASS**。`setup.ps1` 亦会永久写入 Git `bin`/`cmd`。
- **Mac Cursor**：已设 `remote.SSH.remotePlatform.factoros-win=windows`、`remote.SSH.showLoginTerminal=true`。
- **结果**：日志显示 `Resolved authority` + workspace `d:/dev/FactorOS` + Remote ShellExec；Win 侧 `cursor-server`/`node.exe` 在跑。
- 终端用：`D:\dev\FactorOS\.venv\Scripts\python.exe`。手动兜底见 [CONNECT.md](./CONNECT.md)。
- **重活**：`ssh compshare-gpu`，见 [WORK_SPLIT.md](./WORK_SPLIT.md)。

---

## Mac confirmed（给 Windows Cursor 粘贴）

Mac confirmed: SSH PASS (`factoros-win` + `Administrator@192.168.1.114` → SSH_OK); SMB PASS (`/Volumes/FactorOS_Data` mounted, bidirectional RW vs `D:\FactorOS_Data`); RDP port 3389 PASS (`nc`); Mac IP still **192.168.13.105** (Wi‑Fi, dual-subnet with Win 192.168.1.114 — IP not stale); Win→Mac ping FAIL is expected (ICMP/firewall), does not block SSH/SMB. Status READY. Heavy compute → `compshare-gpu`, not home Win.

## Windows confirmed（给 Mac Cursor 粘贴）

Windows confirmed 2026-08-06 ~11:35 CST (independent local re-check): `sshd` Running/Automatic, :22 LISTENING, firewall FactorOS SSH Allow, Mac pubkey in both authorized_keys; ESTABLISHED SSH from 192.168.1.106; `D:\FactorOS_Data` + SMB share + local RW OK; `D:\dev\FactorOS` HEAD `629654d` (.venv pandas 3.0.5 / numpy 2.5.1 / pyarrow 25.0.0); IP 192.168.1.114; RDP fDenyTSConnections=0 / 3389 LISTENING; Win→Mac ping FAIL expected; git 2.55 / gh dblahwn / Python 3.12.8. Dirty tree noted (~500 paths, mostly archive deletions) — not blocking READY. Role = storage + light/medium scripts only; heavy jobs → Cloud.
