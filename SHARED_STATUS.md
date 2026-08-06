# FactorOS Windows Node — 共享进度

双端 Cursor（Mac / Windows）对齐用。只写事实，不写密码。

## 双方 Agent 使用规则

1. 阶段变化时更新本文件顶部「当前状态」一行。
2. 动手前先 `git pull`，改完后 `git push` 到本仓库 `main`。
3. 只写可复述的事实；禁止写入密码、token、私钥等密钥。

---

**当前状态：** CODE_SYNCED_SLIM / awaiting SMB mount + Cursor Remote

**更新时间：** 2026-08-06 ~10:21 CST

## 网络与访问

| 项 | 值 |
|---|---|
| Mac | 192.168.13.105 |
| Windows | 192.168.1.114（主机名 PC-202407291635） |
| SSH | Host `factoros-win` **OK**（`Administrator@192.168.1.114`，公钥） |
| 开放端口 | OpenSSH / SMB 445 / RDP 3389 |
| 有线网速 | Ethernet LinkSpeed 1 Gbps |
| SMB 挂载 | 用户须在 Mac Finder ⌘K 挂载 `smb://192.168.1.114/FactorOS_Data`，账号 Administrator（密码仅在对话框输入，本文不写） |

## Windows 机器

| 项 | 值 |
|---|---|
| CPU | i7-7700 |
| 内存 | 16GB RAM |
| GPU | 无独立显卡 |
| 磁盘 | C≈90GB 空闲；D≈139GB 空闲；E≈390GB；F≈317GB |
| Python | 3.12.8 **OK** |
| Git | 2.55 |

## 路径与仓库

| 项 | 值 |
|---|---|
| FactorOS_Data 共享 | `D:\FactorOS_Data`（SMB 目标；大数按需挂载到此） |
| FactorOS 工作树 | `D:\dev\FactorOS` **present**；git HEAD `629654d` on `main`（与 Mac/GitHub 一致） |
| 瘦拷贝 | **SKIPPED** `data/`（~10G）、`backtest_results/`（~7G）、`archive/` — 代码+脚本足够 Remote SSH 开发 |

## 账号与策略（无密码）

- Administrator **已设置密码**（本文不写密码）。
- `LimitBlankPasswordUse` 已设为 `0`。

## 已知问题

- Windows 上 HTTPS `git clone` 私有仓失败（GCM）；优先用 **Mac→Windows SSH 拷贝**。

## 下一步清单

- [x] SSH `factoros-win` 可用
- [x] `D:\dev\FactorOS` 就位且 HEAD 对齐 Mac/GitHub（`629654d`）
- [x] 瘦拷贝策略确认（跳过大目录）
- [x] Python 3.12.8 OK
- [ ] Mac Finder 挂载 SMB → `smb://192.168.1.114/FactorOS_Data`（大数落到 `D:\FactorOS_Data`）
- [ ] Mac Cursor Remote SSH → `factoros-win` → 打开 `D:\dev\FactorOS`
- [ ] 按需安装 Python 依赖

---
