# Mac 连接 Windows FactorOS 节点

Windows 完成 [README.md](./README.md) 与 `setup.ps1` 后，在 **Mac（dingbolin，Wi‑Fi `192.168.13.105`）** 上按下列步骤连接 **Windows（有线 `192.168.1.114`）**。

**双网段事实（2026-08-06 复核）：** Mac 常驻 `192.168.13.x`，Win 在 `192.168.1.x`。Mac→Win 的 **SSH / SMB / RDP:3389 均可**；Win→Mac 的 `ping` 常失败（ICMP / 防火墙），**属预期**，不要用反向 ping 判断节点是否可用。Mac IP `192.168.13.105` 目前 **未变**。

## 1. 连通性测试

```bash
ping -c 3 192.168.1.114
# 更可靠：直接测 SSH（BatchMode）
ssh -o BatchMode=yes -o ConnectTimeout=8 factoros-win "whoami & hostname & echo SSH_OK"
```

若 ping 不通但 SSH 通，可忽略 ICMP。若 SSH 也不通，检查路由器访客隔离、防火墙、子网路由（见 [NETWORK_FIX.md](./NETWORK_FIX.md)）。

## 2. SSH

### 2.1 本机已有私钥

Mac 上对应公钥应已写入 Windows 的 `authorized_keys`（由 `setup.ps1` 配置）。测试：

```bash
ssh -o ConnectTimeout=10 YOUR_WINDOWS_USER@192.168.1.114
```

将 `YOUR_WINDOWS_USER` 换成 Windows 登录名（PowerShell 中 `echo $env:USERNAME`）。

### 2.2 推荐 `~/.ssh/config` 片段

```sshconfig
Host factoros-win
    HostName 192.168.1.114
    User YOUR_WINDOWS_USER
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
```

之后：

```bash
ssh factoros-win
```

### 2.3 远程执行示例

```bash
ssh factoros-win 'powershell -NoProfile -Command "Get-ChildItem D:\\FactorOS_Data"'
```

路径按 Windows 实际数据盘调整（`D:\` 或 `C:\FactorOS_Data`）。

## 3. SMB 挂载数据目录

在访达 **前往 → 连接服务器**（⌘K）：

```
smb://192.168.1.114/FactorOS_Data
```

或使用 Windows 用户名/密码登录。命令行挂载示例：

```bash
mkdir -p ~/mnt/factoros_data
mount_smbfs //YOUR_WINDOWS_USER@192.168.1.114/FactorOS_Data ~/mnt/factoros_data
```

卸载：

```bash
umount ~/mnt/factoros_data
```

建议：大 parquet、回测缓存、数据库副本放在 SMB 路径；Git 工作区仍在 Mac 的 `~/dev/FactorOS`。

## 4. Cursor / VS Code Remote SSH

1. 安装扩展 **Remote - SSH**。
2. 命令面板：**Remote-SSH: Open SSH Configuration File**，加入与上文相同的 `Host factoros-win`。
3. **Remote-SSH: Connect to Host…** → `factoros-win`。
4. 在远程 Windows 上打开文件夹：**`D:\dev\FactorOS`**（代码仓）。数据盘是 `D:\FactorOS_Data`，不要当代码根目录打开。

适合：在 Windows 上跑长时间 Python 任务，Mac 只负责轻量编辑与 Remote 控制面。详见 [WORK_SPLIT.md](./WORK_SPLIT.md)。

## 5. RDP（图形界面排障）

Mac 可使用 **Microsoft Remote Desktop**（App Store）连接 `192.168.1.114`，用于修网络、改共享权限、看任务管理器。

## 6. FactorOS 仓库

主开发仓库（SSH）：

```text
git@github.com:dblahwn/FactorOS.git
```

Mac 工作目录建议：

```text
~/dev/FactorOS
```

Windows **代码仓**（勿 clone 进数据盘）：

```powershell
cd D:\dev
git clone git@github.com:dblahwn/FactorOS.git
# 数据 / 缓存 / 回测 → D:\FactorOS_Data\{data,cache,backtest_results}
```

Windows 需单独生成 SSH 密钥并把 **公钥** 添加到 GitHub；勿复制 Mac 私钥到 Windows。

## 7. 推荐分工（三机）

完整说明见 [WORK_SPLIT.md](./WORK_SPLIT.md)。摘要：

| 任务 | 建议机器 |
|------|----------|
| Cursor UI、轻量编辑、文档、编排 | Mac（`~/dev/FactorOS`） |
| 大体量落盘、轻/中量挨数据脚本 | Windows（`D:\FactorOS_Data` + `D:\dev\FactorOS`） |
| 全历史 / fleet reval / LLM·RFT | Cloud（`ssh compshare-gpu`） |
| 统一数据路径 | SMB `FactorOS_Data` ↔ `D:\FactorOS_Data`（**不是**代码仓） |

完成 SSH + SMB 后，即可把 Windows 当作存储节点；**不要**把全部重算迁到家用 Win。
