#!/usr/bin/env bash
set -e

########################################
# CONFIG
########################################
SERVICE_NAME="xui-watchdog"

WATCHDOG_BIN="/usr/local/bin/xui-watchdog.sh"
MENU_BIN="/usr/local/bin/watchdog"

STATE_DIR="/run/xui-watchdog"
HIGH_FILE="$STATE_DIR/high"
LAST_FILE="$STATE_DIR/last"

LOG_FILE="/var/log/xui-watchdog.log"

SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
TIMER_FILE="/etc/systemd/system/${SERVICE_NAME}.timer"

RAM_RESTART=70     # %
DURATION=120       # seconds
COOLDOWN=600       # seconds

########################################
# ROOT CHECK
########################################
if [[ $EUID -ne 0 ]]; then
  echo "❌ Please run as root"
  exit 1
fi

echo "▶ Installing FINAL x-ui watchdog (SAFE MODE)"

########################################
# CLEAN OLD WATCHDOGS (ALL VERSIONS)
########################################
echo "🧹 Removing old watchdogs..."

# remove cron based
crontab -l 2>/dev/null | grep -v -E 'xui|watchdog' | crontab - || true

# remove old files
rm -f \
  /usr/local/bin/xui-ram-watch.sh \
  /usr/local/bin/xui-ram-guard \
  /usr/local/bin/xui-watchdog \
  /usr/local/bin/xui-watchdog.sh \
  /usr/local/bin/watchdog \
  /var/log/xui-ram-watch.log \
  /var/log/xui-watchdog.log

# remove systemd units
for u in xui-ram-guard xui-watchdog; do
  systemctl stop $u.timer 2>/dev/null || true
  systemctl disable $u.timer 2>/dev/null || true
  systemctl stop $u.service 2>/dev/null || true
  systemctl disable $u.service 2>/dev/null || true
  rm -f /etc/systemd/system/$u.service
  rm -f /etc/systemd/system/$u.timer
done

rm -rf /run/xui-*

systemctl daemon-reexec
systemctl daemon-reload

echo "✅ Old watchdogs removed"

########################################
# CREATE LOG FILE (IMPORTANT)
########################################
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

########################################
# WATCHDOG CORE SCRIPT
########################################
cat > "$WATCHDOG_BIN" <<'EOF'
#!/usr/bin/env bash
set -e

STATE_DIR="/run/xui-watchdog"
HIGH_FILE="$STATE_DIR/high"
LAST_FILE="$STATE_DIR/last"
LOG="/var/log/xui-watchdog.log"

RAM_RESTART=70
DURATION=120
COOLDOWN=600

mkdir -p "$STATE_DIR"

RAM_USED=$(free | awk '/Mem:/ {printf "%.0f", $3/$2*100}')
NOW=$(date +%s)

if (( RAM_USED < RAM_RESTART )); then
  rm -f "$HIGH_FILE"
  exit 0
fi

[[ ! -f "$HIGH_FILE" ]] && echo "$NOW" > "$HIGH_FILE"

START=$(cat "$HIGH_FILE")
ELAPSED=$((NOW - START))

(( ELAPSED < DURATION )) && exit 0

if [[ -f "$LAST_FILE" ]]; then
  LAST=$(cat "$LAST_FILE")
  (( NOW - LAST < COOLDOWN )) && exit 0
fi

echo "$NOW" > "$LAST_FILE"
rm -f "$HIGH_FILE"

systemctl restart x-ui
echo "$(date) RESTART x-ui RAM=${RAM_USED}%" >> "$LOG"

# trim log
tail -n 2000 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
EOF

chmod +x "$WATCHDOG_BIN"

########################################
# SYSTEMD SERVICE
########################################
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=x-ui RAM Watchdog

[Service]
Type=oneshot
ExecStart=$WATCHDOG_BIN
EOF

########################################
# SYSTEMD TIMER
########################################
cat > "$TIMER_FILE" <<EOF
[Unit]
Description=Run x-ui watchdog every minute

[Timer]
OnBootSec=60
OnUnitActiveSec=60
AccuracySec=10s

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now ${SERVICE_NAME}.timer

########################################
# MENU (SAFE – NO x-ui OVERRIDE)
########################################
cat > "$MENU_BIN" <<EOF
#!/usr/bin/env bash

LOG="$LOG_FILE"

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

case "\$c" in
1)
  tail -n 30 "\$LOG"
  read -p "Enter..."
  ;;
2)
  echo "Ctrl+C เพื่อออก"
  tail -f "\$LOG"
  ;;
3)
  systemctl status ${SERVICE_NAME}.timer --no-pager
  read -p "Enter..."
  ;;
4)
  systemctl restart ${SERVICE_NAME}.timer
  echo "✔ restarted"
  sleep 1
  ;;
5)
  systemctl stop ${SERVICE_NAME}.timer
  echo "✔ stopped"
  sleep 1
  ;;
6)
  systemctl start ${SERVICE_NAME}.timer
  echo "✔ started"
  sleep 1
  ;;
0) exit ;;
*) echo "❌ เลือกไม่ถูก"; sleep 1 ;;
esac
done
EOF

chmod +x "$MENU_BIN"

########################################
# DONE
########################################
echo
echo "========================================"
echo "✅ FINAL x-ui watchdog installed (SAFE)"
echo "• RAM ≥ ${RAM_RESTART}% → restart x-ui"
echo "• Duration : ${DURATION}s"
echo "• Cooldown : ${COOLDOWN}s"
echo
echo "Run menu:"
echo "  watchdog"
echo
echo "x-ui command is untouched ✔"
echo "========================================"
