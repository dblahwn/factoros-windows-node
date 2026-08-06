# Cursor Remote → Windows FactorOS（速查）

前置已就绪：`Host factoros-win`（`~/.ssh/config`）、公钥登录、`D:\dev\FactorOS` HEAD 对齐。

## 三步打开远程仓库

1. Cursor 命令面板 → **Remote-SSH: Connect to Host…** → 选 `factoros-win`
2. 连接后 **File → Open Folder…** → `D:\dev\FactorOS`
3. 终端用 venv：`D:\dev\FactorOS\.venv\Scripts\python.exe`（已装 pandas / numpy / pyarrow）

CLI 自检（Mac）：

```bash
ssh factoros-win "cd /d D:\dev\FactorOS && git log -1 --oneline"
```

## SMB 数据盘

- 共享：`smb://192.168.1.114/FactorOS_Data` → Windows `D:\FactorOS_Data`
- Mac 挂载点（已挂时）：`/Volumes/FactorOS_Data`
- 占位目录：`cache/`、`backtest_results/`、`data/`
- **未同步**：Mac 侧大体量 `data/`、`backtest_results/`（瘦拷贝策略）；大文件按需拷到本共享

卸载：`umount /Volumes/FactorOS_Data`（或访达推出）。
