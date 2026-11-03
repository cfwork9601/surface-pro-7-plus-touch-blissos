#!/bin/bash
set -e

# ==============================================================================
# connect.sh - Smart ADB Reconnect & Wake Utility for Surface Pro 7+
# ==============================================================================

TARGET="${1:-192.168.1.107:5555}"
IP="${TARGET%:*}"

echo "==> Checking ADB connection to $TARGET..."

# If device is already connected
if adb -s "$TARGET" get-state >/dev/null 2>&1; then
    echo "Device $TARGET is already connected."
else
    # Try pinging Wi-Fi target
    if [[ "$TARGET" == *":5555"* ]]; then
        echo "Pinging $IP..."
        if ! ping -c 1 -W 1 "$IP" >/dev/null 2>&1; then
            echo "Host $IP is unreachable over Wi-Fi. Checking USB connections..."
            USB_DEV=$(adb devices | grep -v "List of" | grep -v "offline" | grep -v ":" | grep -v "emulator" | awk '{print $1}' | head -n 1)
            if [ -n "$USB_DEV" ]; then
                echo "Found USB device: $USB_DEV"
                TARGET="$USB_DEV"
            else
                echo "ERROR: Device not found on Wi-Fi ($IP) or USB."
                echo "Tips:"
                echo "  1. Tap the physical Power button on the tablet to wake screen."
                echo "  2. Connect USB-C cable between Surface and host machine."
                exit 1
            fi
        fi
    fi

    echo "Connecting to $TARGET..."
    adb connect "$TARGET" || true
    sleep 1
fi

echo "==> Ensuring root access..."
adb -s "$TARGET" root >/dev/null 2>&1 || true
sleep 1
adb connect "$TARGET" >/dev/null 2>&1 || true

echo "==> Preventing screen timeout during debugging..."
# Same effect as 'svc power stayon true' (7 = AC|USB|wireless), but uses native
# 'cmd settings'. Do NOT use svc/monkey/uiautomator as root here: app_process
# tools leak /proc/cpuinfo bind mounts (see configs/init/cpuinfo_mount_fix.rc).
adb -s "$TARGET" shell "settings put global stay_on_while_plugged_in 7 2>/dev/null || true"
adb -s "$TARGET" shell "settings put system screen_off_timeout 1800000 2>/dev/null || true"

echo "==> Connected successfully to $TARGET!"
adb -s "$TARGET" shell "getprop ro.product.model; uname -r"
