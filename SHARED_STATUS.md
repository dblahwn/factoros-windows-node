# SHARED_STATUS — 冷数据迁 Windows（2026-08-06）

## 目标

Mac 磁盘 ~98% 满；按 `WORK_SPLIT.md` 把冷数据迁到 `D:\FactorOS_Data`。

## 已做（Mac 侧）

| 动作 | 结果 |
|---|---|
| 删 `llm_rft_pilot/astock_18y_train_extract.db`（留 `.gz`） | ✅ ~2GB |
| 删 `llm_rft_pilot/db_chunks` | ✅ ~0.9GB |
| 清部分 `Library/Caches`（ollama-install / Homebrew / pip / VSCode ShipIt） | ✅ |
| 写迁移脚本 | `factoros_windows_node/mac/migrate_cold_data_to_win.sh` |

## 阻塞

| 项 | 状态 |
|---|---|
| Windows SSH | **挂**：TCP:22 通，但 `kex_exchange_identification: Connection closed`（大流量 tar 后 sshd 异常） |
| 首次整包 tar 传 `llm_rft_pilot` | 中途 broken pipe，未完整落盘 |

## 你需要做的（1 步）

**重启 Windows 家用机**（电源键或 RDP 若还能进），然后在 Mac：

```bash
bash factoros_windows_node/mac/win_ctl.sh wait-up 180
bash factoros_windows_node/mac/migrate_cold_data_to_win.sh
# 校验后腾盘：
PURGE=1 bash factoros_windows_node/mac/migrate_cold_data_to_win.sh
```

将迁：`llm_rft_pilot`、部分回测产物、`archive`/`cache`、`data/reports`、`astock_18y.db` 副本。

> 行情库迁走后，Mac 纸盘周更需 SMB 挂载或从 Win 拉回；脚本跑通后会再改 symlink。

## 仍留 Mac（活数据）

- `~/dev/FactorOS` 代码  
- 纸盘 / monitor / 小状态 JSON  
- 在 Win 未稳定前：**先保留** `data/astock_18y.db` 本机副本  
