#!/bin/bash
# ==============================================================================
# status.sh - Comprehensive Diagnostic Status for Surface Pro 7+ on Bliss OS
# ==============================================================================

TARGET="${1:-192.168.1.107:5555}"

echo "=================================================================="
echo " Surface Pro 7+ Diagnostic Status: $TARGET"
echo "=================================================================="

# Check ADB state
STATE=$(adb -s "$TARGET" get-state 2>/dev/null || echo "offline")
echo "ADB State: $STATE"
if [ "$STATE" != "device" ]; then
    echo "Device is not connected. Run ./scripts/connect.sh first."
    exit 1
fi

echo ""
echo "--- System & Build Info ---"
adb -s "$TARGET" shell "
echo 'Model:          ' \$(getprop ro.product.model)
echo 'Bliss Build:    ' \$(getprop ro.bliss.build)
echo 'Android Version:' \$(getprop ro.build.version.release)
echo 'Kernel:         ' \$(uname -r)
echo 'Uptime:         ' \$(uptime | sed 's/^[ \t]*//')
"

echo ""
echo "--- IPTSD Touch Daemon Status ---"
adb -s "$TARGET" shell "
PID=\$(pidof iptsd 2>/dev/null || true)
if [ -n \"\$PID\" ]; then
    echo \"IPTSD PID:        \$PID (RUNNING)\"
    ps -fp \"\$PID\" 2>/dev/null || ps -o PID,USER,STAT,ARGS -p \"\$PID\" 2>/dev/null
else
    echo \"IPTSD PID:        NOT RUNNING! (CRITICAL)\"
fi
"

echo ""
echo "--- Raw ITHC Event Node Watchdog ---"
adb -s "$TARGET" shell "
RAW_NODES=\$(for namefile in /sys/class/input/event*/device/name; do
    if [ -f \"\$namefile\" ]; then
        case \"\$(cat \"\$namefile\" 2>/dev/null)\" in
            *\"Intel Touch Host Controller\"*)
                evnode=\"/dev/input/\$(basename \$(dirname \$(dirname \"\$namefile\")))\"
                if [ -e \"\$evnode\" ]; then echo \"\$evnode\"; fi
                ;;
        esac
    fi
done)

if [ -z \"\$RAW_NODES\" ]; then
    echo \"Raw ITHC Nodes:   CLEANED (No conflict with EventHub)\"
else
    echo \"WARNING: Conflicting Raw ITHC nodes exist: \$RAW_NODES\"
fi
"

echo ""
echo "--- Android EventHub Touch Devices ---"
adb -s "$TARGET" shell "
dumpsys input | grep -B 2 -A 10 'IPTSD Virtual Touchscreen' | head -n 12
"

echo ""
echo "--- Active Configuration Values ---"
adb -s "$TARGET" shell "
echo 'Neutral Setting: ' \$(grep '^Neutral ' /data/vendor/iptsd.conf 2>/dev/null || echo 'not found')
echo 'Deadzone (Min):  ' \$(grep '^PositionThresholdMin ' /data/vendor/iptsd.conf 2>/dev/null || echo 'not found')
echo 'Orientation Max: ' \$(grep '^OrientationThresholdMax ' /data/vendor/iptsd.conf 2>/dev/null || echo 'not found')
echo 'Size Max:        ' \$(grep '^SizeMax ' /data/vendor/iptsd.conf 2>/dev/null || echo 'not found')
"

echo "=================================================================="
