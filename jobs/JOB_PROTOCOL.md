# Windows 无头作业协议（inbox / outbox）

Windows 无显示器，当 **存储 + 轻量执行机**。Mac（编排端）下发任务，Windows 跑完把结果写回 outbox，Mac 再读。

## 目录（Windows）

```
D:\FactorOS_Data\jobs\
  inbox\      # Mac 放入 <job_id>.json
  running\    # Windows 正在跑
  outbox\     # 完成：<job_id>\result.json + stdout.log + 产物
  failed\     # 失败：同上
  keepalive   # Mac touch 此文件 = 「别关机」（2h 空闲看门狗看 mtime）
```

Mac 经 SMB：`/Volumes/FactorOS_Data/jobs/...`（需已挂载）。

## 任务文件 `inbox/<job_id>.json`

```json
{
  "id": "job_20260806_demo",
  "cmd": "D:\\dev\\FactorOS\\.venv\\Scripts\\python.exe -c \"print('hello')\"",
  "cwd": "D:\\dev\\FactorOS",
  "timeout_sec": 3600,
  "created_by": "mac"
}
```

- `cmd`：交给 `cmd.exe /c` 执行（勿交互）
- `cwd`：可选，默认 `D:\dev\FactorOS`
- `timeout_sec`：可选，默认 7200

## 结果 `outbox/<job_id>/result.json`

```json
{
  "id": "job_20260806_demo",
  "status": "ok",
  "exit_code": 0,
  "started_at": "...",
  "finished_at": "...",
  "stdout_log": "stdout.log",
  "stderr_log": "stderr.log"
}
```

失败则在 `failed/<job_id>/`，`status` 为 `error` / `timeout`。

## 电源策略

| 动作 | 谁做 |
|------|------|
| 需要 Windows | Mac：`./mac/win_ctl.sh wake` / `wait-up`（WOL） |
| 有活要干 | Mac：`submit`；Windows worker 消费 inbox |
| 想保活 | Mac：`keepalive`；或 **正在 RDP**；或近期有键鼠输入 |
| 空闲关机 | 见下（过夜无头必须能关） |
| 立刻关机 | Mac：`shutdown` |
| 取消关机 | Mac：`cancel-shutdown`；Windows：桌面「取消 FactorOS 关机」/ `C:\FactorOS\jobs\CANCEL_SHUTDOWN.bat` / `shutdown /a` / 弹窗「否」 |

### 空闲关机怎么判定（过夜无头优先）

**真正保活（任一成立 → 不询问、不关机，并中止 pending）**：

1. **活跃 RDP**（`rdp-tcp#N` Active / 活动；忽略 `rdp-tcp Listen`）
2. **近期输入**（`quser` IDLE TIME &lt; 2h）— 正在打字/操作
3. **inbox/running 任务**，或 keepalive mtime 未超过 2h
4. **用户已取消**（cancel flag / `CANCEL_SHUTDOWN.bat` / `shutdown /a`）

**明确不保活（过夜必须能关）**：

- 仅残留 **Cursor / explorer** 等后台进程、无近期输入
- 控制台名义上仍 Active，但 `quser` 空闲已 ≥2h（ghost session）
- 旧逻辑每 5 分钟因「有用户程序」刷新 `last_activity` → 已废除

仅当以上保活全无，且空闲 ≥ **2 小时** → **先询问**：

- `shutdown /s /t 3600` + pending + 尽量弹窗 / `msg`
- 「否」/ bat / `shutdown /a` / Mac `cancel-shutdown` / keepalive → 取消并重置
- **询问后 1 小时无回复** → `/t 60` 强制关机（无头无人点弹窗也会关）

> 正在 RDP/打字时不应误关；过夜离开且未 `keepalive` 时应自动关。取消：桌面「取消 FactorOS 关机」。

**关机后再测 WOL：** `./mac/wol_selftest.sh`

重活仍走 Cloud（`compshare-gpu`），不要往 Windows inbox 塞重型 fleet/LLM。

## 相关脚本

- Windows：`watchdog.ps1` / `ask_shutdown.ps1` / `CANCEL_SHUTDOWN.bat` / `install_watchdog.ps1` / `worker_once.ps1`
- Mac：`mac/win_ctl.sh`、`mac/wol_selftest.sh`
