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

echo "==> Installing cpuinfo mount-leak fix (init rc)..."
$ADB_CMD push "$CONFIG_DIR/init/cpuinfo_mount_fix.rc" /system/etc/init/cpuinfo_mount_fix.rc
$ADB_CMD shell "chmod 644 /system/etc/init/cpuinfo_mount_fix.rc; chcon u:object_r:system_file:s0 /system/etc/init/cpuinfo_mount_fix.rc 2>/dev/null || true"

echo "==> Installing GPU minimum clock (600 MHz) boot setting..."
$ADB_CMD push "$CONFIG_DIR/init/gpu_min_freq.rc" /system/etc/init/gpu_min_freq.rc
$ADB_CMD shell "chmod 644 /system/etc/init/gpu_min_freq.rc; chcon u:object_r:system_file:s0 /system/etc/init/gpu_min_freq.rc 2>/dev/null || true"
$ADB_CMD shell "echo 600 > /sys/class/drm/card0/gt_min_freq_mhz" || true

echo "==> Setting 2052x1368 render size (SurfaceFlinger cap + wm override, centred boot logo)..."
$ADB_CMD shell "grep -q '^ro.surface_flinger.max_graphics_width=' /system/build.prop || printf '\n# Render at 2052x1368 from first frame (centred boot logo); see docs/CHANGELOG.md\nro.surface_flinger.max_graphics_width=2052\nro.surface_flinger.max_graphics_height=1368\n' >> /system/build.prop"
$ADB_CMD shell "wm size 2052x1368; wm density 240" || true

echo "==> Installing SD-card app network fix (boot service)..."
$ADB_CMD push "$CONFIG_DIR/sd_app_network_fix.sh" /system/etc/sd_app_network_fix.sh
$ADB_CMD push "$CONFIG_DIR/init/sd_app_network_fix.rc" /system/etc/init/sd_app_network_fix.rc
$ADB_CMD shell "chmod 755 /system/etc/sd_app_network_fix.sh; chmod 644 /system/etc/init/sd_app_network_fix.rc; chcon u:object_r:system_file:s0 /system/etc/sd_app_network_fix.sh /system/etc/init/sd_app_network_fix.rc 2>/dev/null || true"

echo "==> Installing touchpad gestures (3-finger up = Recents, 4-finger up = Home)..."
$ADB_CMD push "$CONFIG_DIR/touchpad_gestures.sh" /system/etc/touchpad_gestures.sh
$ADB_CMD push "$CONFIG_DIR/init/touchpad_gestures.rc" /system/etc/init/touchpad_gestures.rc
$ADB_CMD shell "chmod 755 /system/etc/touchpad_gestures.sh; chmod 644 /system/etc/init/touchpad_gestures.rc; chcon u:object_r:system_file:s0 /system/etc/touchpad_gestures.sh /system/etc/init/touchpad_gestures.rc 2>/dev/null || true"

# Settings app (optional; build it with: cd gesture-app && ./gradlew assembleDebug)
GESTURE_APK="$SCRIPT_DIR/gesture-app/app/build/outputs/apk/debug/app-debug.apk"
if [ -f "$GESTURE_APK" ]; then
    echo "==> Installing Touchpad Gestures settings app..."
    $ADB_CMD install -r "$GESTURE_APK" >/dev/null
    # Create the app's files dir (owned by the app) so the daemon can report status into it.
    $ADB_CMD shell "run-as dev.surface.touchpadgestures mkdir -p files" || true
else
    echo "    (settings app not built; skipping. Gestures still work with defaults.)"
fi

echo "==> Installing Boot to Windows script..."
$ADB_CMD push "$CONFIG_DIR/boot_to_windows.sh" /system/etc/boot_to_windows.sh
$ADB_CMD shell "chmod 755 /system/etc/boot_to_windows.sh; chcon u:object_r:system_file:s0 /system/etc/boot_to_windows.sh 2>/dev/null || true"

# Boot to Windows app (optional; build it with: cd bootswitch-app && JAVA_HOME=~/opt/jdk17 ./gradlew assembleDebug)
BOOTSWITCH_APK="$SCRIPT_DIR/bootswitch-app/app/build/outputs/apk/debug/app-debug.apk"
if [ -f "$BOOTSWITCH_APK" ]; then
    echo "==> Installing Boot to Windows app (grant it root in KernelSU > Superuser)..."
    $ADB_CMD install -r "$BOOTSWITCH_APK" >/dev/null
else
    echo "    (Boot to Windows app not built; skipping.)"
fi

echo "==> Restarting touch services..."
$ADB_CMD shell "stop iptsd_runner 2>/dev/null || true; killall iptsd 2>/dev/null || true; sleep 1; start iptsd_runner; sleep 1; sync"

echo "==> Verifying IPTSD process..."
if $ADB_CMD shell "ps -A | grep iptsd" >/dev/null 2>&1; then
    echo "SUCCESS: IPTSD touch service is running!"
    echo "Smooth multitouch and virtual joystick dragging are now active."
else
    echo "WARNING: IPTSD process not found. Check 'adb shell logcat' for details."
fi
