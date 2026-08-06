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
| 需要 Windows | Mac：`./mac/win_ctl.sh wake`（WOL）→ 等 SSH |
| 有活要干 | Mac：`submit`；Windows `worker` 消费 inbox |
| 想保活但不投稿 | Mac：`./mac/win_ctl.sh keepalive` |
| 空闲 2h | Windows **看门狗自动关机** |
| 立刻关机 | Mac：`./mac/win_ctl.sh shutdown` |

重活仍走 Cloud（`compshare-gpu`），不要往 Windows inbox 塞重型 fleet/LLM。

## 相关脚本

- Windows：`watchdog.ps1` / `install_watchdog.ps1` / `worker_once.ps1`
- Mac：`mac/win_ctl.sh`
