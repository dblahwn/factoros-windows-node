# FactorOS Windows Node — 共享进度

双端 Cursor（Mac / Windows）对齐用。只写事实，不写密码。

## 双方 Agent 使用规则

1. 阶段变化时更新本文件顶部「当前状态」一行。
2. 动手前先 `git pull`，改完后 `git push` 到本仓库 `main`。
3. 只写可复述的事实；禁止写入密码、token、私钥等密钥。

---

**当前状态：** Mac↔Win 已打通 SSH；代码已拷至 `D:\dev\FactorOS`（待核验）；下一步挂载 SMB / Remote SSH。

**更新时间：** 2026-08-06 ~10:18 CST

## 网络与访问

| 项 | 值 |
|---|---|
| Mac | 192.168.13.105 |
| Windows | 192.168.1.114（主机名 PC-202407291635） |
| SSH | Host `factoros-win` 可用（`Administrator@192.168.1.114`，公钥） |
| 开放端口 | OpenSSH / SMB 445 / RDP 3389 |
| 有线网速 | Ethernet LinkSpeed 1 Gbps |

## Windows 机器

| 项 | 值 |
|---|---|
| CPU | i7-7700 |
| 内存 | 16GB RAM |
| GPU | 无独立显卡 |
| 磁盘 | C≈90GB 空闲；D≈139GB 空闲；E≈390GB；F≈317GB |
| Python | 3.12.8 |
| Git | 2.55 |

## 路径与仓库

| 项 | 值 |
|---|---|
| FactorOS_Data 共享 | `D:\FactorOS_Data`（空） |
| FactorOS 工作树 | `D:\dev\FactorOS` 已存在且含 `.git`（约 2026-08-06 10:09 拷贝） |
| 拷贝注意 | 若 tar 曾中断，树可能不完整，需核验 |

## 账号与策略（无密码）

- Administrator **已设置密码**（本文不写密码）。
- `LimitBlankPasswordUse` 已设为 `0`。

## 已知问题

- Windows 上 HTTPS `git clone` 私有仓失败（GCM）；优先用 **Mac→Windows SSH 拷贝**。

## 下一步清单

- [ ] 在 Windows 核验 `D:\dev\FactorOS`：`git status` / 完整性
- [ ] Mac Finder 挂载 SMB（FactorOS_Data 等）
- [ ] Cursor Remote SSH 打开 `D:\dev\FactorOS`
- [ ] 按需安装 Python 依赖

