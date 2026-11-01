#!/bin/bash
set -e

# ==============================================================================
# Surface Pro 7+ Touch & Multitouch Installer for Bliss OS / Android-x86
# Target Hardware: Microsoft Surface Pro 7+ (Tiger Lake, ITHC/IPTS 045E:0C1A)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/configs"

ADB_CMD="adb"
if [ -n "$1" ]; then
    ADB_CMD="adb -s $1"
fi

echo "==> Checking ADB connection..."
$ADB_CMD get-state >/dev/null 2>&1 || {
    echo "Error: Device not found or offline. Please specify device: ./install.sh <IP:PORT or SERIAL>"
    exit 1
}

echo "==> Restarting ADB as root..."
$ADB_CMD root >/dev/null 2>&1 || true
sleep 1

echo "==> Remounting system partitions as read-write..."
$ADB_CMD shell "mount -o remount,rw / 2>/dev/null || mount -o remount,rw /system 2>/dev/null || true"

echo "==> Installing IPTSD configuration..."
$ADB_CMD shell "mkdir -p /data/vendor /vendor/etc/ipts"
$ADB_CMD push "$CONFIG_DIR/iptsd.conf" /data/vendor/iptsd.conf
$ADB_CMD shell "cp /data/vendor/iptsd.conf /vendor/etc/iptsd.conf"
$ADB_CMD shell "chmod 644 /data/vendor/iptsd.conf /vendor/etc/iptsd.conf"

# Also ensure preset directory has matching surface-pro-7+.conf
$ADB_CMD shell "cat << 'EOF' > /vendor/etc/ipts/surface-pro-7+.conf
[Device]
Vendor = 0x045E
Product = 0x0C1A

[Config]
InvertX = true
InvertY = true

Width = 25.98
Height = 17.32
EOF
chmod 644 /vendor/etc/ipts/surface-pro-7+.conf
"

echo "==> Installing IPTSD runner daemon script..."
$ADB_CMD push "$CONFIG_DIR/iptsd_runner" /system/vendor/bin/iptsd_runner
$ADB_CMD shell "chmod 755 /system/vendor/bin/iptsd_runner"

echo "==> Installing Android IDC (Input Device Configuration) files..."
$ADB_CMD shell "mkdir -p /system/usr/idc /data/system/devices/idc"
$ADB_CMD push "$CONFIG_DIR/idc/Vendor_045e_Product_0c1a.idc" /system/usr/idc/Vendor_045e_Product_0c1a.idc
$ADB_CMD push "$CONFIG_DIR/idc/IPTSD_Virtual_Touchscreen_045E_0C1A.idc" /system/usr/idc/IPTSD_Virtual_Touchscreen_045E_0C1A.idc
$ADB_CMD shell "cp /system/usr/idc/Vendor_045e_Product_0c1a.idc /data/system/devices/idc/"
$ADB_CMD shell "cp /system/usr/idc/IPTSD_Virtual_Touchscreen_045E_0C1A.idc /data/system/devices/idc/"
$ADB_CMD shell "chmod 644 /system/usr/idc/Vendor_045e_Product_0c1a.idc /system/usr/idc/IPTSD_Virtual_Touchscreen_045E_0C1A.idc /data/system/devices/idc/*.idc"

echo "==> Restarting touch services..."
$ADB_CMD shell "stop iptsd_runner 2>/dev/null || true; killall iptsd 2>/dev/null || true; sleep 1; start iptsd_runner; sleep 1; sync"

echo "==> Verifying IPTSD process..."
if $ADB_CMD shell "ps -A | grep iptsd" >/dev/null 2>&1; then
    echo "SUCCESS: IPTSD touch service is running!"
    echo "Smooth multitouch and virtual joystick dragging are now active."
else
    echo "WARNING: IPTSD process not found. Check 'adb shell logcat' for details."
fi
