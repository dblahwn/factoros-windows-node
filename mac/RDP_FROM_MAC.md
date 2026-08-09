# Mac 上看 Windows 桌面（无显示器）

Windows 已开远程桌面（RDP `3389`）。Mac 上用一个窗口控制即可。

## 安装（一次）

App Store 搜 **Windows App**（微软官方，原 Microsoft Remote Desktop）并安装。  
若已弹出 App Store，直接点获取。

## 连接

1. 打开 **Windows App**
2. 点 **+** / Add PC
3. PC name：`192.168.1.114`（或 `factoros-win` 若已解析）
4. User account：`Administrator` + 你的 Windows 密码
5. 连接 → 会出现 Windows 桌面窗口

也可双击下载里的配置：`~/Downloads/FactorOS-Windows.rdp`

## 注意

- Windows 要开机（或先 `win_ctl.sh wait-up` 唤醒）
- 无物理显示器时，部分机器需在 BIOS/板载显卡开「无头」；若黑屏，SSH 仍可用，可再装虚拟显示器驱动（可选）
- 日常写代码仍优先 **Cursor Remote SSH**；RDP 只用于装软件、看图形界面
