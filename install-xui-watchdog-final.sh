#!/usr/bin/env bash
set -e

############################################
# CONFIG
############################################
SERVICE_NAME="xui-watchdog"

WATCHDOG_BIN="/usr/local/bin/xui-watchdog.sh"
MENU_BIN="/usr/local/bin/x-ui-watchdog"
ALIAS_BIN="/usr/local/bin/x-ui"

LOG_FILE="/var/log/xui-watchdog.log"

RAM_RESTART=80        # %
DURATION=120          # seconds
COOLDOWN=600          # seconds

STATE_DIR="/run/xui-watchdog"
HIGH_FILE="$STATE_DIR/high_since"
LAST_FILE="$STATE_DIR/last_restart"

SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
TIMER_FILE="/etc/systemd/system/${SERVICE_NAME}.timer"

############################################
# ROOT CHECK
############################################
[[ $EUID -ne 0 ]] && echo "❌ run as root" && exit 1

echo "▶ Installing FINAL x-ui watchdog (restart-only)"

############################################
# REMOVE OLD WATCHDOGS (ALL KNOWN VERSIONS)
############################################
echo "🧹 Removing old watchdogs..."

# cron based
crontab -l 2>/dev/null | grep -v xui | crontab - || true

# files
rm -f \
 /usr/local/bin/xui-ram-watch.sh \
 /usr/local/bin/xui-ram-guard \
 /usr/local/bin/xui-watchdog \
 /usr/local/bin/xui-watchdog.sh \
 /usr/local/bin/x-ui-watchdog \
 /var/log/xui-ram-watch.log \
 /var/log/xui-watchdog.log

# systemd
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

# limit journal (กัน storage โต)
journalctl --rotate || true
journalctl --vacuum-size=50M || true

echo "✅ Old watchdogs removed"

############################################
# CREATE LOG FILE
############################################
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

############################################
# WATCHDOG SCRIPT
############################################
cat > "$WATCHDOG_BIN" <<EOF
#!/usr/bin/env bash
set -e

STATE_DIR="$STATE_DIR"
HIGH_FILE="$HIGH_FILE"
LAST_FILE="$LAST_FILE"
LOG="$LOG_FILE"

RAM_RESTART=$RAM_RESTART
DURATION=$DURATION
COOLDOWN=$COOLDOWN

mkdir -p "\$STATE_DIR"

RAM=\$(free | awk '/Mem:/ {printf "%.0f", \$3/\$2*100}')
NOW=\$(date +%s)

if (( RAM >= RAM_RESTART )); then
  [[ ! -f "\$HIGH_FILE" ]] && echo "\$NOW" > "\$HIGH_FILE"
else
  rm -f "\$HIGH_FILE"
  exit 0
fi

START=\$(cat "\$HIGH_FILE")
ELAPSED=\$((NOW - START))
(( ELAPSED < DURATION )) && exit 0

if [[ -f "\$LAST_FILE" ]]; then
  LAST=\$(cat "\$LAST_FILE")
  (( NOW - LAST < COOLDOWN )) && exit 0
fi

systemctl restart x-ui

echo "\$NOW" > "\$LAST_FILE"
rm -f "\$HIGH_FILE"

echo "\$(date) restart x-ui RAM=\${RAM}%" >> "\$LOG"

# keep log small
tail -n 2000 "\$LOG" > "\$LOG.tmp" && mv "\$LOG.tmp" "\$LOG"
EOF

chmod +x "$WATCHDOG_BIN"

############################################
# SYSTEMD SERVICE
############################################
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=x-ui RAM Watchdog

[Service]
Type=oneshot
ExecStart=$WATCHDOG_BIN
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
AccuracySec=10s

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now "$SERVICE_NAME.timer"

############################################
# MENU
############################################
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
  tail -n 20 "\$LOG"
  read -p "Enter..."
;;
2)
  echo "Ctrl+C เพื่อกลับเมนู"
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
*) sleep 1 ;;
esac
done
EOF

chmod +x "$MENU_BIN"

############################################
# ALIAS: x-ui watchdog
############################################
cat > "$ALIAS_BIN" <<EOF
#!/usr/bin/env bash
[[ "\$1" == "watchdog" ]] && exec $MENU_BIN
echo "Usage: x-ui watchdog"
EOF

chmod +x "$ALIAS_BIN"

############################################
# DONE
############################################
echo
echo "========================================"
echo "✅ FINAL x-ui watchdog installed"
echo "• RAM ≥ ${RAM_RESTART}% → restart x-ui"
echo "• Duration : ${DURATION}s"
echo "• Cooldown : ${COOLDOWN}s"
echo
echo "Run menu:"
echo "  x-ui watchdog"
echo
echo "Logs:"
echo "  tail -f $LOG_FILE"
echo "========================================"
