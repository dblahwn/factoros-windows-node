# FactorOS：三机协同（Mac / Windows / Cloud）

协作机器是 **三台**，不是「什么都往 Windows 搬」。Mac 磁盘内存紧；家用 Windows 磁盘大但 CPU 弱；重活上云。

## 总览

| 机器 | 擅长 | 放什么 | 不放什么 |
|------|------|--------|----------|
| **Mac**（`~/dev/FactorOS`，常 `192.168.13.105`） | 交互 / 编排 | Cursor UI、轻量编辑、文档、Remote/SSH 控制面 | 大体量 `data/`、重型回测、长跑 CPU |
| **Windows 家用机**（`factoros-win` / `192.168.1.114`，i7-7700 / 16GB / 无独显，D/E/F 大盘） | **磁盘** + 轻/中量脚本 | 行情/缓存/回测结果冷热数据（`D:\FactorOS_Data`）、代码检出 `D:\dev\FactorOS`、偶尔脚本、给 Mac 腾盘 | 重型训练、大规模并行/fleet 回测、LLM/RFT、GPU 任务 |
| **Cloud**（`Host compshare-gpu`，`~/.ssh/config` → cpod…compshare.cn） | **算力**（CPU/GPU） | 全历史验证、fleet reval、LLM/RFT、一切需要认真算力的任务 | 当唯一代码源（代码仍以 **GitHub** 为准）；把云当永久唯一数据仓 |

## 路径约定

| 用途 | 位置 |
|------|------|
| 源码真相 | GitHub `dblahwn/FactorOS` |
| Mac 工作树 | `~/dev/FactorOS`（轻量；勿堆 `data/` / `backtest_results/`） |
| Windows 代码检出 | `D:\dev\FactorOS`（Remote-SSH 打开这里） |
| Windows 数据盘 | `D:\FactorOS_Data\{data,cache,backtest_results}`（SMB：`FactorOS_Data`） |
| Mac SMB | `/Volumes/FactorOS_Data` |
| Cloud | 作业目录按实例约定；产物按需回传到 Win 数据盘或 Mac 小子集 |

> **禁止**：`cd D:\FactorOS_Data && git clone …FactorOS`（代码与数据搅在一起）。  
> **禁止**：把「全量重算」默认迁到 Windows — 家用机性能差，只适合存储邻域的轻/中量活。

## 推荐工作流

1. **改代码 / 文档**：Mac Cursor → 本地 `~/dev/FactorOS` → commit / push GitHub。
2. **挨着数据的轻量脚本**（扫盘、小样本、整理产物）：Mac → Remote-SSH `factoros-win` → `D:\dev\FactorOS` + 读写 `D:\FactorOS_Data`；或 Mac 经 SMB 读写数据盘。
3. **重型回测 / 全历史 / fleet / LLM·RFT**：Mac → `ssh compshare-gpu`（或等价 Remote）→ 拉 GitHub 代码跑；大产物优先落云 scratch，再 **选择性** sync 到 `D:\FactorOS_Data`（或只拉摘要回 Mac）。
4. **GitHub 始终是代码源**；三机各自 checkout，勿互拷整仓当主源。
5. **瘦拷贝已跳过** Mac→Win 的大体量 `data/`、`backtest_results/`：需要时 rsync **子集到 Windows 数据盘**，不要反过来灌满 Mac。

## 选型速查

| 任务 | 去哪 |
|------|------|
| 写代码、看文档、盯状态、触发任务 | Mac |
| 存 parquet / 缓存 / 回测结果；给 Mac 腾空间 | Windows `D:\FactorOS_Data`（E/F 不够再扩） |
| 偶尔小脚本、依赖数据盘的中等 CPU | Windows 可以，但别期望快 |
| 全历史 validate、fleet reval、长跑回测 | **Cloud `compshare-gpu`** |
| LLM / RFT / 需要 GPU | **Cloud**（家用 Win 无独显） |

## 电源与无头作业（Windows）

Windows 无显示器，当 **磁盘 + 轻量执行机**：

| 动作 | 命令（Mac） |
|------|-------------|
| 需要开机 | `factoros_windows_node/mac/win_ctl.sh wait-up`（WOL；需 BIOS 开 Wake-on-LAN） |
| 下发任务 | `win_ctl.sh submit <id> '<cmd>'` → 结果在 outbox |
| 取回结果 | `win_ctl.sh fetch <id>` |
| 保活（重置空闲计时） | `win_ctl.sh keepalive` |
| 立刻关机 | `win_ctl.sh shutdown` |
| 空闲 2h | Windows 计划任务 `FactorOS_IdleWatchdog` **自动关机** |

协议详见 [jobs/JOB_PROTOCOL.md](./jobs/JOB_PROTOCOL.md)。重活仍走 Cloud，不要往 Windows inbox 塞 fleet/LLM。

MAC 地址（WOL）：`E0:D5:5E:A3:CC:24` → 广播 `192.168.1.255`。

## 相关文档

- [SHARED_STATUS.md](./SHARED_STATUS.md) — 双端/三机进度（事实）
- [CONNECT.md](./CONNECT.md) — Cursor Remote → Windows 速查
- [MAC_CONNECT.md](./MAC_CONNECT.md) — Mac → Win SSH/SMB
- [jobs/JOB_PROTOCOL.md](./jobs/JOB_PROTOCOL.md) — inbox/outbox + 看门狗
- [README.md](./README.md) — Windows 节点配置总览
