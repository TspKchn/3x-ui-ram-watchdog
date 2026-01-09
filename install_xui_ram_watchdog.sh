#!/usr/bin/env bash
set -e

### ===== CONFIG =====
RAM_THRESHOLD=80          # %
SWAP_THRESHOLD_MB=300     # MB
DURATION=120              # seconds
COOLDOWN=600              # seconds (10 min)
SERVICE="x-ui"

UNIT="/usr/local/bin/xui-ram-guard"
STATE_DIR="/run/xui-ram-guard"
STATE_FILE="$STATE_DIR/high_since"
LAST_RESTART="$STATE_DIR/last_restart"

SERVICE_FILE="/etc/systemd/system/xui-ram-guard.service"
TIMER_FILE="/etc/systemd/system/xui-ram-guard.timer"

### ===== ROOT CHECK =====
if [[ $EUID -ne 0 ]]; then
  echo "❌ run as root"
  exit 1
fi

echo "▶ Installing SAFE x-ui RAM guard"

### ===== GUARD SCRIPT =====
cat > "$UNIT" <<EOF
#!/bin/bash
set -e

mkdir -p "$STATE_DIR"

RAM_USED=\$(free | awk '/Mem:/ {printf "%.0f", \$3/\$2*100}')
SWAP_USED=\$(free | awk '/Swap:/ {printf "%.0f", \$3/1024}')
NOW=\$(date +%s)

over_limit=0
[[ "\$RAM_USED" -ge "$RAM_THRESHOLD" ]] && over_limit=1
[[ "\$SWAP_USED" -ge "$SWAP_THRESHOLD_MB" ]] && over_limit=1

if [[ \$over_limit -eq 1 ]]; then
  [[ ! -f "$STATE_FILE" ]] && echo "\$NOW" > "$STATE_FILE"
else
  rm -f "$STATE_FILE"
  exit 0
fi

START=\$(cat "$STATE_FILE")
ELAPSED=\$((NOW - START))

[[ "\$ELAPSED" -lt "$DURATION" ]] && exit 0

if [[ -f "$LAST_RESTART" ]]; then
  LAST=\$(cat "$LAST_RESTART")
  [[ \$((NOW - LAST)) -lt "$COOLDOWN" ]] && exit 0
fi

echo "\$NOW" > "$LAST_RESTART"
rm -f "$STATE_FILE"

systemctl restart $SERVICE
logger "[xui-ram-guard] restart x-ui RAM=\${RAM_USED}% SWAP=\${SWAP_USED}MB"
EOF

chmod +x "$UNIT"

### ===== SYSTEMD SERVICE =====
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=x-ui RAM Guard

[Service]
Type=oneshot
ExecStart=$UNIT
EOF

### ===== SYSTEMD TIMER =====
cat > "$TIMER_FILE" <<EOF
[Unit]
Description=Run x-ui RAM Guard every minute

[Timer]
OnBootSec=60
OnUnitActiveSec=60
AccuracySec=10s

[Install]
WantedBy=timers.target
EOF

### ===== ENABLE =====
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable --now xui-ram-guard.timer

echo
echo "✅ Installed successfully"
echo "• RAM >= ${RAM_THRESHOLD}% for ${DURATION}s → restart x-ui"
echo "• Cooldown ${COOLDOWN}s"
echo "• Logs: journalctl -t xui-ram-guard"
