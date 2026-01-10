#!/usr/bin/env bash
set -e

############################################
# CONFIG
############################################
RAM_RELOAD=80
RAM_RESTART=90
DURATION=120
COOLDOWN=600

SERVICE="x-ui"

BIN_WATCHDOG="/usr/local/bin/xui-watchdog"
LOG_FILE="/var/log/xui-watchdog.log"

STATE_DIR="/run/xui-watchdog"
STATE_FILE="$STATE_DIR/high_since"
LAST_RESTART="$STATE_DIR/last_restart"

SERVICE_FILE="/etc/systemd/system/xui-watchdog.service"
TIMER_FILE="/etc/systemd/system/xui-watchdog.timer"

############################################
# ROOT CHECK
############################################
[[ $EUID -ne 0 ]] && echo "❌ run as root" && exit 1

echo "▶ Installing FINAL x-ui watchdog"

############################################
# REMOVE OLD WATCHDOGS (ALL VERSIONS)
############################################
echo "🧹 Removing old watchdogs..."

# cron based
crontab -l 2>/dev/null | grep -v xui-ram-watch | crontab - || true
rm -f /usr/local/bin/xui-ram-watch.sh
rm -f /var/log/xui-ram-watch.log
rm -f /tmp/xui_ram_high

# systemd based (old names)
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

# journal cleanup (กัน storage บวม)
journalctl --rotate
journalctl --vacuum-size=50M

echo "✅ Old watchdogs removed"

############################################
# CREATE WATCHDOG ENGINE
############################################
cat > "$BIN_WATCHDOG" <<'EOF'
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

ACTION="none"

if [[ "$RAM_USED" -ge "$RAM_RESTART" ]]; then
  ACTION="restart"
elif [[ "$RAM_USED" -ge "$RAM_RELOAD" ]]; then
  ACTION="reload"
fi

[[ "$ACTION" == "none" ]] && rm -f "$STATE_FILE" && exit 0

[[ ! -f "$STATE_FILE" ]] && echo "$NOW" > "$STATE_FILE"

START=$(cat "$STATE_FILE")
ELAPSED=$((NOW - START))
[[ "$ELAPSED" -lt "$DURATION" ]] && exit 0

if [[ "$ACTION" == "restart" ]]; then
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

chmod +x "$BIN_WATCHDOG"

############################################
# PREPARE LOG
############################################
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

############################################
# SYSTEMD SERVICE
############################################
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=x-ui RAM Watchdog

[Service]
Type=oneshot
ExecStart=$BIN_WATCHDOG
EOF

############################################
# SYSTEMD TIMER
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

systemctl daemon-reload
systemctl enable --now xui-watchdog.timer

############################################
# X-UI WRAPPER (FINAL)
############################################
if [ ! -f /usr/local/bin/x-ui.real ]; then
  mv /usr/local/bin/x-ui /usr/local/bin/x-ui.real
fi

cat > /usr/local/bin/x-ui <<'EOF'
#!/usr/bin/env bash
REAL="/usr/local/bin/x-ui.real"
WATCHDOG="/usr/local/bin/xui-watchdog"

if [[ "$1" == "watchdog" ]]; then
  while true; do
    clear
    echo "========= X-UI WATCHDOG ========="
    echo "1) ดู log ล่าสุด"
    echo "2) ดู log realtime"
    echo "3) ดูสถานะ watchdog"
    echo "4) Restart watchdog"
    echo "5) Stop watchdog"
    echo "6) Start watchdog"
    echo "0) Exit"
    echo "==============================="
    read -p "เลือก: " c
    case $c in
      1) tail -n 50 /var/log/xui-watchdog.log; read -p "Enter..." ;;
      2) tail -f /var/log/xui-watchdog.log; read -p "Enter..." ;;
      3) systemctl status xui-watchdog.timer; read -p "Enter..." ;;
      4) systemctl restart xui-watchdog.timer ;;
      5) systemctl stop xui-watchdog.timer ;;
      6) systemctl start xui-watchdog.timer ;;
      0) exit ;;
    esac
  done
fi

exec "$REAL" "$@"
EOF

chmod +x /usr/local/bin/x-ui

############################################
# DONE
############################################
echo
echo "========================================"
echo "✅ FINAL x-ui watchdog installed"
echo "• x-ui watchdog"
echo "• RAM ≥ 80% → reload"
echo "• RAM ≥ 90% → restart"
echo "• Duration ${DURATION}s / Cooldown ${COOLDOWN}s"
echo
echo "ใช้คำสั่ง:"
echo "  x-ui watchdog"
echo "========================================"
