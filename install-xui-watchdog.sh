#!/usr/bin/env bash
set -e

### ================= CONFIG =================
THRESHOLD=80
WATCHDOG_SCRIPT="/usr/local/bin/xui-watchdog.sh"
SERVICE_FILE="/etc/systemd/system/xui-watchdog.service"
TIMER_FILE="/etc/systemd/system/xui-watchdog.timer"

### ================= ROOT CHECK =================
if [[ $EUID -ne 0 ]]; then
    echo "❌ Please run as root"
    exit 1
fi

echo "🔧 Installing 3x-ui RAM watchdog (systemd based)..."

### ================= CLEAN OLD WATCHDOG =================
echo "🧹 Cleaning old cron / watchdog (if any)..."
crontab -l 2>/dev/null | grep -v xui-ram-watch | crontab - 2>/dev/null || true
rm -f /usr/local/bin/xui-ram-watch.sh
rm -f /var/log/xui-ram-watch.log
rm -f /tmp/xui_ram_high
rm -f /etc/systemd/system/xui-ram-guard.service
rm -f /etc/systemd/system/xui-ram-guard.timer

### ================= WATCHDOG SCRIPT =================
cat > "$WATCHDOG_SCRIPT" <<EOF
#!/bin/bash
set -e

THRESHOLD=${THRESHOLD}

RAM_USED=\$(free | awk '/Mem:/ {printf "%.0f", \$3/\$2*100}')

if [ "\$RAM_USED" -ge "\$THRESHOLD" ]; then
    logger -t xui-watchdog "RAM \${RAM_USED}% >= \${THRESHOLD}%, reload x-ui"
    systemctl reload x-ui 2>/dev/null || systemctl restart x-ui
fi
EOF

chmod +x "$WATCHDOG_SCRIPT"

### ================= SYSTEMD SERVICE =================
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=3x-ui RAM Watchdog
After=network.target

[Service]
Type=oneshot
ExecStart=${WATCHDOG_SCRIPT}
EOF

### ================= SYSTEMD TIMER =================
cat > "$TIMER_FILE" <<EOF
[Unit]
Description=Run 3x-ui RAM Watchdog every 2 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=2min
AccuracySec=30s
Persistent=true

[Install]
WantedBy=timers.target
EOF

### ================= ENABLE =================
systemctl daemon-reload
systemctl enable --now xui-watchdog.timer

### ================= DONE =================
echo
echo "======================================"
echo "✅ 3x-ui RAM Watchdog installed"
echo "• Threshold : RAM >= ${THRESHOLD}%"
echo "• Action    : reload x-ui (fallback restart)"
echo "• Interval  : every 2 minutes"
echo
echo "Check status:"
echo "  systemctl list-timers | grep xui"
echo
echo "View logs:"
echo "  journalctl -t xui-watchdog"
echo "======================================"
