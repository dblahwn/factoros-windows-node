# Mac 上看 Windows 桌面（无显示器）

Windows 已开远程桌面（RDP `3389`，`fDenyTSConnections=0`）。Mac 上用 **Windows App** 开一个窗口即可。

## 安装（一次）

App Store 搜 **Windows App**（微软官方，原 Microsoft Remote Desktop）并安装到 `/Applications/Windows App.app`。

## 一键连接（推荐）

配置文件：`~/Downloads/FactorOS-Windows.rdp`

```text
full address:s:192.168.1.114
username:s:Administrator
prompt for credentials:i:1
```

在终端：

```bash
open -a "Windows App" ~/Downloads/FactorOS-Windows.rdp
```

或在 Finder 双击该 `.rdp` 文件。

### 屏幕上应出现什么

1. **Windows App** 置前；可能先出现「Devices / PCs」列表里的 `192.168.1.114`
2. 弹出 **凭据 / 登录** 对话框：用户名已是 `Administrator`，请输入 **Windows 本机密码**，点 **Continue / 继续**
3. 若提示证书不受信任：选 **Continue / 仍要连接**（局域网自签常见）
4. 成功后：出现 **Windows 桌面窗口**（1920×1080），可看到任务栏 / 桌面图标

### 若黑屏

本机已有虚拟显示（`USB Mobile Monitor Virtual Display` + GTX 1060），一般不必再装驱动。  
若仍黑屏：告诉管理员，SSH（`ssh factoros-win`）仍可用，再决定是否补虚拟显示器方案。

## 手动添加 PC（备选）

1. 打开 **Windows App** → **+** / Add PC  
2. PC name：`192.168.1.114`  
3. User account：`Administrator` + Windows 密码  
4. 连接

## 连通性自检（Mac）

```bash
nc -z 192.168.1.114 3389          # 应成功
ssh factoros-win "echo SSH_OK"    # 应打印 SSH_OK
```

Windows 需开机（或先 `factoros_windows_node/mac/win_ctl.sh wait-up` 唤醒）。

## 连上之后建议

- 日常写代码仍优先 **Cursor Remote SSH**；RDP 只用于装软件、看图形界面、点确认对话框  
- 可选：在 Windows 上跑一次关机取消测试（`jobs/CANCEL_SHUTDOWN.bat` / 看 `jobs/JOB_PROTOCOL.md`）  
- 可选：稍后再跑回测 / BT；不必在首次 RDP 登录时做

## 注意

- 无物理显示器时，本机已挂虚拟显示；若黑屏再反馈，勿先强装重型显卡驱动  
- 密码只在 Windows App 凭据框输入，不要写进 `.rdp` 明文
