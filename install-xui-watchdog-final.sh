#!/usr/bin/env bash
set -e

### ================= CONFIG =================
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

### ================= ROOT CHECK =================
[[ $EUID -ne 0 ]] && echo "❌ run as root" && exit 1

echo "▶ Installing FINAL x-ui watchdog"

### ================= CLEAN OLD =================
echo "🧹 Removing old watchdogs..."
crontab -l 2>/dev/null | grep -v xui | crontab - || true

rm -f \
 /usr/local/bin/xui-ram-watch.sh \
 /usr/local/bin/xui-ram-guard \
 /usr/local/bin/xui-watchdog.sh \
 /etc/systemd/system/xui-ram-guard.* \
 /etc/systemd/system/xui-watchdog.* \
 /var/log/xui-ram-watch.log \
 /var/log/xui-watchdog.log

systemctl daemon-reexec
systemctl daemon-reload

journalctl --vacuum-time=7d >/dev/null 2>&1 || true

echo "✅ Old watchdogs removed"

### ================= WATCHDOG SCRIPT =================
cat > "$WATCHDOG_BIN" <<EOF
#!/bin/bash
set -e

mkdir -p "$STATE_DIR"

RAM=\$(free | awk '/Mem:/ {printf "%.0f", \$3/\$2*100}')
NOW=\$(date +%s)

if (( RAM >= $RAM_RELOAD )); then
    [[ ! -f "$HIGH_FILE" ]] && echo "\$NOW" > "$HIGH_FILE"
else
    rm -f "$HIGH_FILE"
    exit 0
fi

START=\$(cat "$HIGH_FILE")
ELAPSED=\$((NOW - START))
(( ELAPSED < $DURATION )) && exit 0

[[ -f "$LAST_FILE" ]] && (( NOW - \$(cat "$LAST_FILE") < $COOLDOWN )) && exit 0

if (( RAM >= $RAM_RESTART )); then
    ACTION="restart"
    systemctl restart x-ui
else
    ACTION="reload"
    systemctl reload x-ui || systemctl restart x-ui
fi

echo "\$NOW" > "$LAST_FILE"
rm -f "$HIGH_FILE"

echo "\$(date) \$ACTION x-ui RAM=\${RAM}%" >> "$LOG_FILE"
tail -n 2000 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
EOF

chmod +x "$WATCHDOG_BIN"

### ================= SYSTEMD =================
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=x-ui RAM Watchdog

[Service]
Type=oneshot
ExecStart=$WATCHDOG_BIN
EOF

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

### ================= MENU =================
cat > "$MENU_BIN" <<EOF
#!/bin/bash
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
1) tail -n 20 "\$LOG"; read -p "Enter..." ;;
2) echo "Ctrl+C เพื่อออก"; tail -f "\$LOG" ;;
3) systemctl status ${SERVICE_NAME}.timer --no-pager; read -p "Enter..." ;;
4) systemctl restart ${SERVICE_NAME}.timer; echo "✔ restarted"; sleep 1 ;;
5) systemctl stop ${SERVICE_NAME}.timer; echo "✔ stopped"; sleep 1 ;;
6) systemctl start ${SERVICE_NAME}.timer; echo "✔ started"; sleep 1 ;;
0) exit ;;
*) echo "❌ ผิด"; sleep 1 ;;
esac
done
EOF

chmod +x "$MENU_BIN"

### ================= ALIAS =================
cat > /usr/local/bin/x-ui <<EOF
#!/bin/bash
[[ "\$1" == "watchdog" ]] && exec $MENU_BIN
echo "Usage: x-ui watchdog"
EOF
chmod +x /usr/local/bin/x-ui

### ================= DONE =================
echo
echo "========================================"
echo "✅ FINAL x-ui watchdog installed"
echo "• RAM ≥ 80% → reload x-ui"
echo "• RAM ≥ 90% → restart x-ui"
echo "• Duration : ${DURATION}s"
echo "• Cooldown : ${COOLDOWN}s"
echo
echo "Run:"
echo "  x-ui watchdog"
echo "========================================"
