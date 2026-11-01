#!/bin/bash
set -e

# ==============================================================================
# screencap.sh - Capture and pull screenshot from Surface Pro 7+
# ==============================================================================

TARGET="${1:-192.168.1.107:5555}"
OUTPUT="${2:-screenshot_$(date +%Y%m%d_%H%M%S).png}"

echo "==> Taking screenshot on $TARGET..."
adb -s "$TARGET" shell "screencap -p /sdcard/screencap_tmp.png"
adb -s "$TARGET" pull /sdcard/screencap_tmp.png "$OUTPUT"
adb -s "$TARGET" shell "rm -f /sdcard/screencap_tmp.png"

echo "Screenshot saved to: $OUTPUT"
