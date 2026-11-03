# Diagnostic & Operation Commands Cheatsheet

All commands assume connection via `adb -s 192.168.1.107:5555` (or `./scripts/connect.sh`).

---

## 1. Quick Helper Scripts
```bash
./scripts/connect.sh          # Auto-reconnect Wi-Fi / USB & elevate to root
./scripts/status.sh           # Display comprehensive subsystem status
./scripts/restart_iptsd.sh    # Safely restart IPTSD touch services
./scripts/screencap.sh        # Pull screenshot from tablet to host
./scripts/pull_backup.sh      # Backup current configs from device
./scripts/cpu_profile.sh [gaming|balance|battery]  # Switch CPU EPP profile (resets on reboot)
./install.sh                  # Deploy complete repository configs to device
```

---

## 2. Touch & IPTSD Diagnostics
```bash
# Check if iptsd process is active
adb shell "ps -A | grep iptsd"

# Test if device node is recognized by IPTSD
adb shell "/vendor/bin/iptsd-check-device /dev/hidraw1"

# Check EventHub input device bindings and active IDC file
adb shell "dumpsys input | grep -B 2 -A 15 'IPTSD Virtual Touchscreen'"

# Stream live touch events from device
adb shell "getevent -l /dev/input/event14"

# View active IPTSD configuration
adb shell "cat /data/vendor/iptsd.conf"
```

---

## 3. Power, Sleep & Display Management
```bash
# Keep screen awake while plugged in (do NOT use `svc power stayon` as root:
# app_process tools leak /proc/cpuinfo mounts, see TROUBLESHOOTING.md §6)
adb shell "settings put global stay_on_while_plugged_in 7"

# Extend screen timeout to 30 minutes
adb shell "settings put system screen_off_timeout 1800000"

# Wake screen remotely
adb shell "input keyevent 26"  # Power toggle
adb shell "input keyevent 82"  # Unlock screen

# Check screen power state
adb shell "dumpsys power | grep -E 'mWakefulness=|Display Power:'"

# Battery percentage in status bar (Settings toggle hidden on this build)
adb shell "settings put system status_bar_show_battery_percent 2"  # 0=off 1=inside icon 2=next to icon

# UI animation speed (currently 0.5x)
adb shell "settings put global window_animation_scale 0.5; settings put global transition_animation_scale 0.5; settings put global animator_duration_scale 0.5"
```

---

## 4. Package & Permission Management
```bash
# Whitelist app from battery idle/doze throttling
adb shell "dumpsys deviceidle whitelist +<package_name>"

# Grant all storage and runtime permissions
adb shell "pm grant <package_name> android.permission.READ_EXTERNAL_STORAGE"
adb shell "pm grant <package_name> android.permission.WRITE_EXTERNAL_STORAGE"
adb shell "appops set <package_name> MANAGE_EXTERNAL_STORAGE allow"
adb shell "appops set <package_name> LEGACY_STORAGE allow"

# Open Play Store directly to an app details page
adb shell "am start -a android.intent.action.VIEW -d 'market://details?id=<package_name>'"
```

---

## 5. Storage & System Partitions
```bash
# Remount system partition as read-write
adb root
adb shell "mount -o remount,rw /"

# Always commit buffers before rebooting or disconnecting
adb shell "sync"
```

---

## 6. Adopted SD Card & Moving Apps
```bash
# MicroSD (64 GB) is adopted as internal storage, volume UUID 14a62407-55be-4b7b-8ac7-f958e8d6260e
adb shell "sm list-volumes all"

# "Not enough storage" when moving an app = missing oat/ dir (status -6). Create it, then move:
adb shell "cmd package compile -m speed-profile -f <package>"
adb shell "pm move-package <package> 14a62407-55be-4b7b-8ac7-f958e8d6260e"
```
