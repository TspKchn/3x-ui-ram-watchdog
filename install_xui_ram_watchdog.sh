#!/usr/bin/env bash
set -e

### ================= CONFIG =================
RAM_THRESHOLD=80        # %
SWAP_THRESHOLD_MB=300   # MB
DURATION=120            # seconds (2 minutes)

WATCHDOG="/usr/local/bin/xui-ram-watch.sh"
LOG="/var/log/xui-ram-watch.log"
CRON_JOB="* * * * * $WATCHDOG"
STATE="/tmp/xui_ram_high"

### ================= ROOT CHECK =================
if [[ $EUID -ne 0 ]]; then
    echo "❌ Please run as root"
    exit 1
fi

echo "✅ Installing x-ui RAM watchdog..."

### ================= CREATE WATCHDOG =================
cat > "$WATCHDOG" <<EOF
#!/bin/bash

LOG="$LOG"
STATE="$STATE"

RAM_USED=\$(free | awk '/Mem:/ {printf "%.0f", \$3/\$2*100}')
SWAP_USED_MB=\$(free | awk '/Swap:/ {printf "%.0f", \$3/1024}')

if [ "\$RAM_USED" -ge "$RAM_THRESHOLD" ] || [ "\$SWAP_USED_MB" -ge "$SWAP_THRESHOLD_MB" ]; then
    if [ ! -f "\$STATE" ]; then
        date +%s > "\$STATE"
    fi

    NOW=\$(date +%s)
    START=\$(cat "\$STATE")
    ELAPSED=\$((NOW - START))

    if [ "\$ELAPSED" -ge "$DURATION" ]; then
        echo "\$(date) restart x-ui RAM=\${RAM_USED}% SWAP=\${SWAP_USED_MB}MB" >> "\$LOG"
        systemctl restart x-ui
        rm -f "\$STATE"
    fi
else
    rm -f "\$STATE"
fi
EOF

chmod +x "$WATCHDOG"

### ================= CREATE LOG =================
touch "$LOG"
chmod 644 "$LOG"

### ================= SET CRON =================
( crontab -l 2>/dev/null | grep -v "$WATCHDOG" ; echo "$CRON_JOB" ) | crontab -

### ================= DONE =================
echo
echo "========================================"
echo "✅ x-ui RAM watchdog installed"
echo "• Threshold  : RAM >= ${RAM_THRESHOLD}%"
echo "• Swap limit : >= ${SWAP_THRESHOLD_MB} MB"
echo "• Duration  : ${DURATION} sec"
echo "• Check every 1 minute"
echo
echo "Watchdog file : $WATCHDOG"
echo "Log file      : $LOG"
echo
echo "Check log with:"
echo "  tail -f $LOG"
echo "========================================"
