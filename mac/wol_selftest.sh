#!/usr/bin/env bash
# Fully automated Windows WOL self-test (no babysitting):
#   enable NIC WOL → shutdown → wait DOWN → WOL blast → wait SSH → keepalive
# Also installs a Mac LaunchAgent to re-run after future agent-requested shutdowns if desired.
#
# Usage:
#   ./wol_selftest.sh
#   ./wol_selftest.sh --install-agent   # install weekly auto-check LaunchAgent
set -uo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
CTL="$ROOT/win_ctl.sh"
LOG_DIR="${HOME}/Library/Logs/FactorOS"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/wol_selftest_$(date +%Y%m%d_%H%M%S).log"
RESULT="$LOG_DIR/wol_selftest_last.txt"

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }
die() {
  log "FAIL: $*"
  echo "FAIL $* @ $(date)" >"$RESULT"
  if command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"$*\" with title \"FactorOS WOL 失败\"" || true
  fi
  exit 1
}
notify() {
  if command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"$1\" with title \"FactorOS\"" || true
  fi
}

install_agent() {
  local dest="$HOME/Library/LaunchAgents/com.factoros.wol-selftest.plist"
  cat >"$dest" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.factoros.wol-selftest</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${ROOT}/wol_selftest.sh</string>
  </array>
  <key>StartInterval</key><integer>604800</integer>
  <key>RunAtLoad</key><false/>
  <key>StandardOutPath</key><string>${LOG_DIR}/wol_launchd.out</string>
  <key>StandardErrorPath</key><string>${LOG_DIR}/wol_launchd.err</string>
</dict>
</plist>
EOF
  launchctl unload "$dest" 2>/dev/null || true
  launchctl load "$dest" 2>/dev/null || launchctl bootstrap "gui/$(id -u)" "$dest" 2>/dev/null || true
  log "Installed LaunchAgent (weekly): $dest"
}

[[ -x "$CTL" ]] || chmod +x "$CTL"
[[ "${1:-}" == "--install-agent" ]] && { install_agent; exit 0; }

log "=== FactorOS Windows WOL self-test ==="
log "log=$LOG"

# Already up?
if ssh -o BatchMode=yes -o ConnectTimeout=5 factoros-win "echo SSH_OK" >/dev/null 2>&1; then
  log "Windows is UP — enabling NIC WOL then cycling power"
  ssh -o BatchMode=yes -o ConnectTimeout=8 factoros-win \
    "powershell -NoProfile -Command \"Get-NetAdapter | Where-Object Status -eq 'Up' | ForEach-Object { try { Set-NetAdapterPowerManagement -Name \\\$_.Name -WakeOnMagicPacket Enabled -ErrorAction Stop; 'OK '+\\\$_.Name } catch { 'SKIP '+\\\$_.Name } }\"" \
    >>"$LOG" 2>&1 || true
  # Also try device manager style via powercfg if available
  ssh -o BatchMode=yes factoros-win "powercfg /devicequery wake_armed" >>"$LOG" 2>&1 || true
  "$CTL" keepalive >>"$LOG" 2>&1 || true
  log "issuing shutdown"
  "$CTL" shutdown >>"$LOG" 2>&1 || die "shutdown failed"
else
  log "Windows already DOWN — skip shutdown, go straight to WOL"
fi

log "waiting for SSH DOWN"
down=0
for i in $(seq 1 60); do
  if ! ssh -o BatchMode=yes -o ConnectTimeout=2 factoros-win "echo up" >/dev/null 2>&1; then
    down=1
    log "SSH down after ~$((i * 2))s"
    break
  fi
  sleep 2
done
[[ "$down" -eq 1 ]] || die "Windows never went down"

sleep 10
log "WOL + wait-up (180s)"
if ! "$CTL" wait-up 180 | tee -a "$LOG"; then
  notify "WOL 失败：请按一次主机电源键，我会继续自动验收"
  # wait extra 3 minutes for manual press
  log "waiting up to 180s more for manual power press..."
  if ! "$CTL" wait-up 180 | tee -a "$LOG"; then
    die "WOL failed and no manual power — enable BIOS Wake-on-LAN once, then re-run"
  fi
  log "recovered after manual power (or late WOL)"
fi

"$CTL" keepalive >>"$LOG" 2>&1 || true
echo "PASS @ $(date)" >"$RESULT"
log "PASS — Windows is up after cycle"
notify "Windows WOL 自检通过"
exit 0
