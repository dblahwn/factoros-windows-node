# FactorOS Windows Node — 共享进度

双端对齐用。只写事实，不写密码。分工见 [WORK_SPLIT.md](./WORK_SPLIT.md)。

**当前状态：** HEADLESS_WORKER_READY + **WOL_SELFTEST_PASS**（2026-08-06 13:29：关机→WOL→SSH ~10s）

**更新时间：** 2026-08-06 ~13:30 CST

## 电源 / 无头作业（已通）

| 项 | 值 |
|---|---|
| SSH | `ssh factoros-win` OK（开机后复核） |
| WOL | NIC `WakeOnMagicPacket=Enabled`；自检 `mac/wol_selftest.sh` **PASS** |
| 空闲关机 | `FactorOS_IdleWatchdog` 每 5 分钟；无任务/keepalive 超过 **2h** → 关机 |
| Mac 控制 | `mac/win_ctl.sh`（wake/wait-up/shutdown/keepalive/submit/fetch） |
| 自动复检 | LaunchAgent `com.factoros.wol-selftest`（周检） |
| 作业目录 | `D:\FactorOS_Data\jobs\{inbox,running,outbox,failed}` |

## 冷数据迁移（进行中）

Mac 盘紧；脚本：`mac/migrate_cold_data_to_win.sh` → `D:\FactorOS_Data`。

| 项 | 状态 |
|---|---|
| 删本地大库碎片（llm_rft 等） | 部分已做（见历史） |
| 整包 tar 曾 broken pipe / sshd 异常 | 开机后 SSH 已恢复；大文件请改 **分块 scp**，勿一次巨型 tar |
| 下一步 | Mac 跑迁移脚本；重活仍走 `compshare-gpu` |

## 路径速查

| 用途 | 路径 |
|---|---|
| Win 代码 | `D:\dev\FactorOS` |
| Win 数据 | `D:\FactorOS_Data` |
| Mac 编排 | `~/dev/FactorOS` + `factoros_windows_node/mac/win_ctl.sh` |
| Cloud | `Host compshare-gpu` |
