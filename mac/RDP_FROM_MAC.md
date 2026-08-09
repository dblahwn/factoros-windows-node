# Mac 上看 Windows 桌面（无显示器）

Windows 已开远程桌面（RDP `3389`，`fDenyTSConnections=0`）。Mac 上用 **Windows App** 开一个普通窗口即可（不必全屏）。

## 安装（一次）

App Store 搜 **Windows App**（微软官方，原 Microsoft Remote Desktop）并安装到 `/Applications/Windows App.app`。

## 一键连接（推荐）

配置文件：

- `~/Downloads/FactorOS-Windows.rdp`（本机快捷）
- `factoros_windows_node/mac/FactorOS-Windows.rdp`（仓库副本，同内容）

已设为 **窗口模式**（非全屏）+ **LAN 画质**：1440×900、32bpp、关闭压缩、字体平滑、`connection type:i:6`（LAN）。

在终端：

```bash
open -a "Windows App" ~/Downloads/FactorOS-Windows.rdp
```

或在 Finder 双击该 `.rdp` 文件。**改完 `.rdp` 后请重新打开连接**（旧会话不会自动套用新参数）。

### 屏幕上应出现什么

1. **Windows App** 置前；可能先出现「Devices / PCs」列表里的 `192.168.1.114`
2. 弹出 **凭据 / 登录** 对话框：用户名已是 `Administrator`，请输入 **Windows 本机密码**，点 **Continue / 继续**
3. 若提示证书不受信任：选 **Continue / 仍要连接**（局域网自签常见）
4. 成功后：出现 **普通 Mac 窗口** 里的 Windows 桌面（约 1440×900），可看到任务栏 / 桌面图标——**不是全屏**

### 若当前已是全屏，立刻退出

任选其一：

- 快捷键：**Ctrl + Option + Break**（部分键盘无 Break：试 **Ctrl + Option + Fn + F12**，或笔记本 **Ctrl + Option + Pause**）
- 菜单：**View（显示）→ Exit Full Screen / 退出全屏**，或 **Window → Restore**
- 把鼠标移到屏幕**最顶端**，出现连接栏 / 工具条后点 **退出全屏 / 还原窗口**（restore）

退出后应变成可拖动、可缩放的普通 Mac 窗口。

### Windows App 偏好（画质 / 窗口）

1. 打开 **Windows App** → **Preferences / 偏好设置**（或菜单 **Windows App → Settings**）
2. **Display / 显示**：
   - 尽量选较高画质 / Quality（若有）
   - Retina / HiDPI：可按清晰度与流畅度自行开关（清晰优先可开；卡顿则关）
   - 会话以 **窗口（Windowed）** 启动，不要默认 Full Screen
3. **网络 / 连接类型**：若有选项，选 **LAN**（与 `.rdp` 里 `connection type:i:6` 一致）
4. 关掉旧会话后，用更新后的 `.rdp` **重新连接**

说明：Mac Wi‑Fi ↔ Windows 有线、双网段时，画质仍可能略受限；在 App 里强制 **LAN** + 本仓库 `.rdp` 的 LAN 参数一般最稳。

### 若黑屏

本机已有虚拟显示（`USB Mobile Monitor Virtual Display` + GTX 1060），一般不必再装驱动。  
若仍黑屏：告诉管理员，SSH（`ssh factoros-win`）仍可用，再决定是否补虚拟显示器方案。

## 手动添加 PC（备选）

1. 打开 **Windows App** → **+** / Add PC  
2. PC name：`192.168.1.114`  
3. User account：`Administrator` + Windows 密码  
4. Display：窗口模式、较高质量 / LAN（勿强制全屏）  
5. 连接

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
- 画质：优先用本文件配套的 `.rdp`（窗口 + LAN）；仍糊时在 Preferences 强制 LAN 并重连
