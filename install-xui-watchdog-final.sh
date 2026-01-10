#!/usr/bin/env bash
set -e

############################################
# CONFIG
############################################
SERVICE_NAME="xui-watchdog"

WATCHDOG_BIN="/usr/local/bin/xui-watchdog.sh"
MENU_BIN="/usr/local/bin/x-ui-watchdog"
LOG_FILE="/var/log/xui-watchdog.log"

RAM_RELOAD=80
RAM_RESTART=90
DURATION=120
COOLDOWN=600

STATE_DIR="/run/xui-watchdog"
HIGH_FILE="$STATE_DIR/high"
LAST_FILE="$STATE_DIR/last"

SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
TIMER_FILE="/etc/systemd/system/${SERVICE_NAME}.timer"

############################################
# ROOT CHECK
############################################
if [[ $EUID -ne 0 ]]; then
  echo "❌ run as root"
  exit 1
fi

echo "▶ Installing FINAL x-ui watchdog"

############################################
# CLEAN OLD WATCHDOGS (ALL VERSIONS)
############################################
echo "🧹 Removing old watchdogs..."

# remove cron based
crontab -l 2>/dev/null | grep -v xui | crontab - || true

# remove old files
rm -f \
 /usr/local/bin/xui-ram-watch.sh \
 /usr/local/bin/xui-ram-guard \
 /usr/local/bin/xui-watchdog \
 /usr/local/bin/xui-watchdog.sh \
 /usr/local/bin/x-ui-watchdog \
 /etc/systemd/system/xui-ram-guard.* \
 /etc/systemd/system/xui-watchdog.* \
 /var/log/xui-ram-watch.log \
 /var/log/xui-watchdog.log

rm -rf /run/xui-watchdog*

systemctl daemon-reexec
systemctl daemon-reload

# cleanup journal (กัน storage โต)
journalctl --rotate >/dev/null 2>&1 || true
journalctl --vacuum-time=7d >/dev/null 2>&1 || true

echo "✅ Old watchdogs removed"

############################################
# CREATE WATCHDOG SCRIPT
############################################
cat > "$WATCHDOG_BIN" <<EOF
#!/bin/bash
set -e

STATE_DIR="$STATE_DIR"
HIGH_FILE="$HIGH_FILE"
LAST_FILE="$LAST_FILE"
LOG="$LOG_FILE"

RAM_RELOAD=$RAM_RELOAD
RAM_RESTART=$RAM_RESTART
DURATION=$DURATION
COOLDOWN=$COOLDOWN

mkdir -p "\$STATE_DIR"

RAM=\$(free | awk '/Mem:/ {printf "%.0f", \$3/\$2*100}')
NOW=\$(date +%s)

if (( RAM >= RAM_RELOAD )); then
    [[ ! -f "\$HIGH_FILE" ]] && echo "\$NOW" > "\$HIGH_FILE"
else
    rm -f "\$HIGH_FILE"
    exit 0
fi

START=\$(cat "\$HIGH_FILE")
ELAPSED=\$((NOW - START))
(( ELAPSED < DURATION )) && exit 0

if [[ -f "\$LAST_FILE" ]]; then
    (( NOW - \$(cat "\$LAST_FILE") < COOLDOWN )) && exit 0
fi

if (( RAM >= RAM_RESTART )); then
    ACTION="RESTART"
    systemctl restart x-ui
else
    ACTION="RELOAD"
    systemctl reload x-ui 2>/dev/null || systemctl restart x-ui
fi

echo "\$NOW" > "\$LAST_FILE"
rm -f "\$HIGH_FILE"

echo "\$(date) \$ACTION x-ui RAM=\${RAM}%" >> "\$LOG"

# limit log size
tail -n 2000 "\$LOG" > "\$LOG.tmp" && mv "\$LOG.tmp" "\$LOG"
EOF

chmod +x "$WATCHDOG_BIN"

############################################
# CREATE LOG FILE (สำคัญ)
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
systemctl enable --now ${SERVICE_NAME}.timer

############################################
# MENU COMMAND (x-ui watchdog)
############################################
cat > "$MENU_BIN" <<EOF
#!/bin/bash
LOG="$LOG_FILE"

touch "\$LOG"
chmod 644 "\$LOG"

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
    echo "----- LAST LOG -----"
    tail -n 20 "\$LOG" 2>/dev/null || echo "(ยังไม่มี log)"
    echo "--------------------"
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
0)
    exit
;;
*)
    echo "❌ ผิด"
    sleep 1
;;
esac
done
EOF

chmod +x "$MENU_BIN"

############################################
# x-ui watchdog COMMAND
############################################
cat > /usr/local/bin/x-ui <<EOF
#!/bin/bash
if [[ "\$1" == "watchdog" ]]; then
    exec $MENU_BIN
fi
echo "Usage: x-ui watchdog"
EOF
chmod +x /usr/local/bin/x-ui

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
echo "Run:"
echo "  x-ui watchdog"
echo "========================================"
