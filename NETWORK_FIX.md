# Windows 外网极慢 — 排查摘要

在配置 OpenSSH、winget、Git 克隆之前，**先让 Windows 能正常访问 GitHub**。否则安装与更新会超时或极慢。

## 常见原因（按优先级）

### 1. VPN / 系统代理 / 浏览器插件代理

- 关闭 **全局 VPN**（或改为「仅浏览器」/ 分流），再测速。
- **设置 → 网络和 Internet → 代理**：关闭「使用代理服务器」（除非你有明确的内网代理且知道地址）。
- 检查是否安装了 **Clash / v2ray / 公司安全客户端**，退出或配置「绕过局域网与中国大陆直连」。
- PowerShell 中查看环境代理：
  ```powershell
  netsh winhttp show proxy
  ```
  若不需要代理：
  ```powershell
  netsh winhttp reset proxy
  ```

### 2. 网卡链路速度协商错误（有线常见）

症状：局域网正常，但外网吞吐极低，或 CPU 占用高。

1. **设备管理器 → 网络适配器 → 你的有线网卡 → 属性 → 高级**。
2. 查看 **Speed & Duplex（速度和双工）**：
   - 先尝试 **1.0 Gbps Full Duplex**（若交换机/路由器支持）。
   - 若不稳定，改为 **100 Mbps Full Duplex** 做对比测试。
3. 更换网线、换路由器端口，排除物理层问题。

### 3. DNS 慢或污染

```powershell
# 测试解析与连通
nslookup github.com
curl.exe -I -m 15 https://github.com
```

可临时将 DNS 改为运营商或公共 DNS（如 `223.5.5.5` / `119.29.29.29`），在 **网卡 IPv4 属性** 中设置，改后 `ipconfig /flushdns`。

### 4. Windows Update / 后台占满带宽

- **设置 → Windows 更新**：暂停更新或安排在非工作时间。
- 任务管理器 → **性能 → 以太网**：观察是否有异常持续上传/下载。

### 5. 安全软件 / 流量扫描

第三方杀毒或「网络加速」类软件可能对 HTTPS 做中间人扫描，导致极慢。临时禁用或为 `git.exe`、`python.exe` 添加排除项做对比。

## 快速验收（修复后应满足）

在 **PowerShell** 中：

```powershell
curl.exe -o NUL -w "time_total=%{time_total}s\n" -m 30 https://github.com
```

- 正常家庭宽带：`time_total` 通常在 **1–5 秒** 量级（视地区而定）。
- 若 **>30 秒超时**，继续查 VPN/代理/网卡双工。

```powershell
winget search Git.Git
```

应在合理时间内返回结果。

## 与 FactorOS 工作流的关系

- **Mac（192.168.13.105）**：主开发、Git push/pull、Cursor。
- **Windows（192.168.1.114）**：大文件存储、长时间回测；可通过 **SMB** 从 Mac 读写 `FactorOS_Data`，通过 **SSH** 跑远程命令。

外网慢只影响 **在 Windows 本机** 安装软件或 `git clone`；修复后，Mac 仍可通过局域网 SSH/SMB 使用 Windows，即使 Windows 外网一般，也可由 Mac 同步代码与数据。

## 子网不同（13.x vs 1.x）

若 Mac 为 `192.168.13.x`、Windows 为 `192.168.1.x`：这是当前常态（双网段）。路由器需允许跨子网转发且 **没有隔离 AP/访客网络**。

- **Mac→Win**：SSH（22）、SMB（445）、RDP（3389）已在 2026-08-06 复核通过；互 ping **不是**硬性门槛。
- **Win→Mac ping 失败**：常见且可接受（Mac 防火墙挡 ICMP）；只要 Mac 能 SSH/SMB 到 Win 即可继续工作。
- 必要时为两台设备绑定静态 IP，或调整 VLAN/访客网络设置。
