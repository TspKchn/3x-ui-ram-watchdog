#!/usr/bin/env bash
set -e

############################################
# CONFIG
############################################
RAM_RELOAD=80        # % → reload x-ui
RAM_RESTART=90       # % → restart x-ui
DURATION=120         # seconds over threshold
COOLDOWN=600         # seconds between restarts

SERVICE_NAME="x-ui"

UNIT_BIN="/usr/local/bin/xui-watchdog"
STATE_DIR="/run/xui-watchdog"
STATE_FILE="$STATE_DIR/high_since"
LAST_RESTART="$STATE_DIR/last_restart"

SERVICE_FILE="/etc/systemd/system/xui-watchdog.service"
TIMER_FILE="/etc/systemd/system/xui-watchdog.timer"

LOG_FILE="/var/log/xui-watchdog.log"

############################################
# ROOT CHECK
############################################
if [[ $EUID -ne 0 ]]; then
  echo "❌ Please run as root"
  exit 1
fi

echo "▶ Installing FINAL x-ui watchdog"

############################################
# STEP 1: REMOVE OLD WATCHDOGS (ALL VERSIONS)
############################################
echo "🧹 Removing old watchdogs..."

# ---- old cron-based ----
if crontab -l 2>/dev/null | grep -q xui-ram-watch.sh; then
  crontab -l 2>/dev/null | grep -v xui-ram-watch.sh | crontab -
fi
rm -f /usr/local/bin/xui-ram-watch.sh
rm -f /var/log/xui-ram-watch.log
rm -f /tmp/xui_ram_high

# ---- old systemd-based ----
for u in xui-ram-guard xui-watchdog; do
  systemctl stop $u.timer 2>/dev/null || true
  systemctl disable $u.timer 2>/dev/null || true
  systemctl stop $u.service 2>/dev/null || true
  systemctl disable $u.service 2>/dev/null || true
  rm -f /etc/systemd/system/$u.service
  rm -f /etc/systemd/system/$u.timer
  rm -f /usr/local/bin/$u
  rm -rf /run/$u*
done

systemctl daemon-reexec
systemctl daemon-reload

# ---- journal cleanup (CRITICAL) ----
journalctl --rotate
journalctl --vacuum-size=50M

echo "✅ Old watchdogs removed"

############################################
# STEP 2: CREATE WATCHDOG SCRIPT
############################################
echo "⚙ Creating watchdog binary..."

cat > "$UNIT_BIN" <<'EOF'
#!/usr/bin/env bash
set -e

STATE_DIR="/run/xui-watchdog"
STATE_FILE="$STATE_DIR/high_since"
LAST_RESTART="$STATE_DIR/last_restart"
LOG="/var/log/xui-watchdog.log"
SERVICE="x-ui"

RAM_RELOAD=80
RAM_RESTART=90
DURATION=120
COOLDOWN=600

mkdir -p "$STATE_DIR"

RAM_USED=$(free | awk '/Mem:/ {printf "%.0f", $3/$2*100}')
NOW=$(date +%s)

over=0
action="none"

if [[ "$RAM_USED" -ge "$RAM_RESTART" ]]; then
  over=1
  action="restart"
elif [[ "$RAM_USED" -ge "$RAM_RELOAD" ]]; then
  over=1
  action="reload"
fi

if [[ "$over" -eq 0 ]]; then
  rm -f "$STATE_FILE"
  exit 0
fi

[[ ! -f "$STATE_FILE" ]] && echo "$NOW" > "$STATE_FILE"

START=$(cat "$STATE_FILE")
ELAPSED=$((NOW - START))

[[ "$ELAPSED" -lt "$DURATION" ]] && exit 0

if [[ "$action" == "restart" ]]; then
  if [[ -f "$LAST_RESTART" ]]; then
    LAST=$(cat "$LAST_RESTART")
    [[ $((NOW - LAST)) -lt "$COOLDOWN" ]] && exit 0
  fi
  echo "$NOW" > "$LAST_RESTART"
  systemctl restart "$SERVICE"
  echo "$(date) RESTART x-ui RAM=${RAM_USED}%" >> "$LOG"
else
  systemctl reload "$SERVICE" 2>/dev/null || systemctl restart "$SERVICE"
  echo "$(date) RELOAD x-ui RAM=${RAM_USED}%" >> "$LOG"
fi

rm -f "$STATE_FILE"
EOF

chmod +x "$UNIT_BIN"
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

############################################
# STEP 3: SYSTEMD SERVICE
############################################
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=FINAL x-ui RAM Watchdog

[Service]
Type=oneshot
ExecStart=$UNIT_BIN
EOF

############################################
# STEP 4: SYSTEMD TIMER
############################################
cat > "$TIMER_FILE" <<EOF
[Unit]
Description=Run x-ui watchdog every minute

[Timer]
OnBootSec=60
OnUnitActiveSec=60
AccuracySec=15s

[Install]
WantedBy=timers.target
EOF

############################################
# STEP 5: ENABLE
############################################
systemctl daemon-reload
systemctl enable --now xui-watchdog.timer

############################################
# DONE
############################################
echo
echo "========================================"
echo "✅ FINAL x-ui watchdog installed"
echo "• RAM ≥ ${RAM_RELOAD}% → reload x-ui"
echo "• RAM ≥ ${RAM_RESTART}% → restart x-ui"
echo "• Duration : ${DURATION}s"
echo "• Cooldown : ${COOLDOWN}s"
echo
echo "Logs:"
echo "  tail -f $LOG_FILE"
echo
echo "Status:"
echo "  systemctl status xui-watchdog.timer"
echo "========================================"
