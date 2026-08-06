#!/usr/bin/env bash
# Mac control plane for headless Windows worker (factoros-win).
set -uo pipefail

HOST_ALIAS="${WIN_SSH_HOST:-factoros-win}"
WIN_IP="${WIN_IP:-192.168.1.114}"
WIN_MAC="${WIN_MAC:-E0:D5:5E:A3:CC:24}"
WIN_BROADCAST="${WIN_BROADCAST:-192.168.1.255}"
REPO_WIN='D:\dev\FactorOS'

usage() {
  cat <<'EOF'
Usage: win_ctl.sh <command> [args]

  status       Ping SSH; list inbox/running/outbox
  wake         Wake-on-LAN magic packet (BIOS/NIC WOL must be on)
  wait-up      wake + wait until SSH works (default 180s)
  shutdown     SSH shutdown /s /t 10
  keepalive    Touch jobs/keepalive (resets 2h idle timer)
  submit <id> <cmd> [cwd] [timeout_sec]
  fetch <id>   Print outbox/failed result.json
  worker       Run one worker cycle on Windows now
  demo         Submit tiny python job and wait for result

Env: WIN_SSH_HOST WIN_IP WIN_MAC WIN_BROADCAST
EOF
}

ssh_win() {
  ssh -o BatchMode=yes -o ConnectTimeout=8 "$HOST_ALIAS" "$@"
}

cmd_status() {
  if ping -c 1 -W 1000 "$WIN_IP" >/dev/null 2>&1; then
    echo "ping: ok ($WIN_IP)"
  else
    echo "ping: fail ($WIN_IP) — may be off or booting"
  fi
  if ssh_win "echo SSH_OK" 2>/dev/null; then
    ssh_win 'cmd /c "echo ---inbox---& dir /b D:\FactorOS_Data\jobs\inbox 2>nul & echo ---running---& dir /b D:\FactorOS_Data\jobs\running 2>nul & echo ---outbox---& dir /b D:\FactorOS_Data\jobs\outbox 2>nul & echo ---failed---& dir /b D:\FactorOS_Data\jobs\failed 2>nul"'
  else
    echo "ssh: down"
    return 1
  fi
}

cmd_wake() {
  python3 - "$WIN_MAC" "$WIN_BROADCAST" "$WIN_IP" <<'PY'
import socket, sys, time
mac = sys.argv[1]
targets = [sys.argv[2], "255.255.255.255", sys.argv[3]]
mac_bytes = bytes.fromhex(mac.replace(":", "").replace("-", ""))
assert len(mac_bytes) == 6
packet = b"\xff" * 6 + mac_bytes * 16
ports = (9, 7)
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
s.settimeout(1)
sent = []
for _ in range(3):
  for host in targets:
    for port in ports:
      try:
        s.sendto(packet, (host, port))
        sent.append(f"{host}:{port}")
      except OSError as e:
        sent.append(f"{host}:{port}!{e}")
  time.sleep(0.2)
s.close()
print("WOL blast:", ", ".join(dict.fromkeys(sent)))
PY
  if command -v wakeonlan >/dev/null 2>&1; then
    wakeonlan -i "$WIN_BROADCAST" "$WIN_MAC" || true
  fi
}

cmd_wait_up() {
  local timeout="${1:-180}"
  cmd_wake || true
  local i=0
  while (( i < timeout )); do
    if ssh -o BatchMode=yes -o ConnectTimeout=2 -o ServerAliveInterval=1 \
         "$HOST_ALIAS" "echo SSH_OK" 2>/dev/null; then
      echo "up after ${i}s"
      cmd_keepalive || true
      return 0
    fi
    # re-blast WOL every 30s
    if (( i > 0 && i % 30 == 0 )); then
      cmd_wake || true
    fi
    sleep 2
    i=$((i + 2))
    echo "waiting ssh... ${i}s"
  done
  echo "timeout waiting for SSH (check BIOS Wake-on-LAN / press power once)" >&2
  if command -v osascript >/dev/null 2>&1; then
    osascript -e 'display notification "Windows WOL 失败，请按一下主机电源键" with title "FactorOS"' || true
  fi
  return 1
}

cmd_shutdown() {
  ssh_win "shutdown /s /t 10 /c FactorOS-Mac-win_ctl"
  echo "shutdown issued (/t 10)"
}

cmd_keepalive() {
  ssh_win "cmd /c echo keepalive> D:\\FactorOS_Data\\jobs\\keepalive"
  echo "keepalive touched"
}

cmd_submit() {
  local id="${1:?job id}"
  local cmd="${2:?cmd}"
  local cwd="${3:-$REPO_WIN}"
  local timeout="${4:-7200}"
  local tmp
  tmp="$(mktemp)"
  python3 - "$id" "$cmd" "$cwd" "$timeout" >"$tmp" <<'PY'
import json, sys
print(json.dumps({
  "id": sys.argv[1],
  "cmd": sys.argv[2],
  "cwd": sys.argv[3].replace("/", "\\"),
  "timeout_sec": int(sys.argv[4]),
  "created_by": "mac",
}, ensure_ascii=False))
PY
  ssh_win "cmd /c if not exist D:\\FactorOS_Data\\jobs\\inbox mkdir D:\\FactorOS_Data\\jobs\\inbox"
  scp -o BatchMode=yes -o ConnectTimeout=8 "$tmp" "${HOST_ALIAS}:/D:/FactorOS_Data/jobs/inbox/${id}.json" \
    || scp -o BatchMode=yes -o ConnectTimeout=8 "$tmp" "${HOST_ALIAS}:D:/FactorOS_Data/jobs/inbox/${id}.json"
  rm -f "$tmp"
  cmd_keepalive
  ssh_win "powershell -NoProfile -ExecutionPolicy Bypass -File C:\\FactorOS\\jobs\\watchdog.ps1" || true
  echo "submitted $id"
}

cmd_fetch() {
  local id="${1:?job id}"
  local out
  out="$(ssh_win "type D:\\FactorOS_Data\\jobs\\outbox\\${id}\\result.json" 2>/dev/null)" && {
    printf '%s\n' "$out"
    return 0
  }
  out="$(ssh_win "type D:\\FactorOS_Data\\jobs\\failed\\${id}\\result.json" 2>/dev/null)" && {
    printf '%s\n' "$out"
    return 0
  }
  echo "NOT_READY"
  return 1
}

cmd_worker() {
  ssh_win "powershell -NoProfile -ExecutionPolicy Bypass -File C:\\FactorOS\\jobs\\worker_once.ps1"
}

cmd_demo() {
  local id="demo_$(date +%Y%m%d_%H%M%S)"
  cmd_submit "$id" 'D:/dev/FactorOS/.venv/Scripts/python.exe -c "print(\"demo_ok\")"'
  local i=0
  while (( i < 90 )); do
    out="$(cmd_fetch "$id" 2>/dev/null || true)"
    if [[ -n "$out" && "$out" != *NOT_READY* ]]; then
      echo "$out"
      return 0
    fi
    sleep 2
    i=$((i + 2))
  done
  echo "demo timeout" >&2
  return 1
}

main() {
  local c="${1:-}"
  shift || true
  case "$c" in
    status) cmd_status "$@" ;;
    wake) cmd_wake "$@" ;;
    wait-up) cmd_wait_up "$@" ;;
    shutdown) cmd_shutdown "$@" ;;
    keepalive) cmd_keepalive "$@" ;;
    submit) cmd_submit "$@" ;;
    fetch) cmd_fetch "$@" ;;
    worker) cmd_worker "$@" ;;
    demo) cmd_demo "$@" ;;
    ""|-h|--help|help) usage ;;
    *) echo "unknown: $c" >&2; usage; return 1 ;;
  esac
}

main "$@"
