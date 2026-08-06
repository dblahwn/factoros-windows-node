#!/usr/bin/env bash
# Migrate cold FactorOS artifacts Mac → Windows D:\FactorOS_Data via scp (chunk-safe).
set -euo pipefail
HOST="${WIN_SSH_HOST:-factoros-win}"
REPO="${FACTOROS_REPO:-$HOME/dev/FactorOS}"
LOG="$REPO/factor_os/backtest_results/migrate_cold_to_win.log"
CTL="$(cd "$(dirname "$0")" && pwd)/win_ctl.sh"

log(){ echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }
ssh_ok(){ ssh -o BatchMode=yes -o ConnectTimeout=12 "$HOST" "echo OK" >/dev/null 2>&1; }

scp_path(){
  local src="$1" dest_win="$2"  # dest like D:/FactorOS_Data/backtest_results/
  [[ -e "$src" ]] || { log "SKIP $src"; return 0; }
  log "SCP $src -> $HOST:$dest_win"
  ssh "$HOST" "cmd /c mkdir \"${dest_win//\//\\}\" 2>nul" || true
  # For directories, scp -r; for large files also fine
  scp -r -o ServerAliveInterval=15 -o ServerAliveCountMax=20 -o Compression=no \
    "$src" "$HOST:$dest_win"
}

main(){
  mkdir -p "$(dirname "$LOG")"
  log "=== migrate start ==="
  if ! ssh_ok; then
    log "Windows SSH down — waking…"
    bash "$CTL" wake || true
    bash "$CTL" wait-up 180 || { log "FAIL: reboot Windows then retry"; exit 2; }
  fi
  bash "$CTL" keepalive || true

  scp_path "$REPO/factor_os/backtest_results/llm_rft_pilot" "D:/FactorOS_Data/backtest_results/"
  scp_path "$REPO/factor_os/backtest_results/port_value_q_001_protocol_r" "D:/FactorOS_Data/backtest_results/"
  scp_path "$REPO/factor_os/archive" "D:/FactorOS_Data/archive/"
  scp_path "$REPO/factor_os/cache" "D:/FactorOS_Data/cache/"
  scp_path "$REPO/data/reports" "D:/FactorOS_Data/"
  scp_path "$REPO/data/astock_18y.db" "D:/FactorOS_Data/data/"

  log "Verify remote sizes…"
  ssh "$HOST" 'powershell -NoProfile -Command "
    \$p=@(\"D:\\FactorOS_Data\\backtest_results\\llm_rft_pilot\",\"D:\\FactorOS_Data\\data\\astock_18y.db\");
    foreach(\$x in \$p){ if(Test-Path \$x){ if((Get-Item \$x).PSIsContainer){ \$s=(Get-ChildItem \$x -Recurse -File|Measure-Object Length -Sum).Sum } else { \$s=(Get-Item \$x).Length }; Write-Output (\"{0} {1:N1} MB\" -f \$x, (\$s/1MB)) } else { Write-Output \"MISSING \$x\" } }
  "'

  if [[ "${PURGE:-0}" == "1" ]]; then
    log "PURGE Mac cold copies (keep astock_18y.db on Mac until SMB ready)"
    rm -rf "$REPO/factor_os/backtest_results/llm_rft_pilot"
    rm -rf "$REPO/factor_os/backtest_results/port_value_q_001_protocol_r"
    rm -rf "$REPO/factor_os/archive" "$REPO/factor_os/cache"
    # reports can stay small; optional
    log "PURGED"
  fi
  log "=== done ==="
}
main "$@"
