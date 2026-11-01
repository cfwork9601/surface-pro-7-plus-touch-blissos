#!/bin/bash
set -e

# ==============================================================================
# restart_iptsd.sh - Cleanly Restart Touch Services on Surface Pro 7+
# ==============================================================================

TARGET="${1:-192.168.1.107:5555}"

echo "==> Restarting IPTSD on $TARGET..."
adb -s "$TARGET" root >/dev/null 2>&1 || true

adb -s "$TARGET" shell "
stop iptsd_runner 2>/dev/null || true
killall iptsd 2>/dev/null || true
sleep 1
start iptsd_runner
sleep 1
sync
"

echo "==> Verifying new process..."
adb -s "$TARGET" shell "ps -A | grep iptsd"
echo "Done! Touch services restarted."
