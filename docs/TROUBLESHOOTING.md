# Troubleshooting Guide & Known Gotchas

## 1. ADB "No route to host" / Device Offline
- **Cause**: When the tablet screen turns off, Bliss OS enters deep suspend, powering down the Intel AX201 Wi-Fi interface to conserve power.
- **Resolution**:
  1. Press the physical Power button on top of the tablet to wake the screen.
  2. Run `./scripts/connect.sh`.
  3. Keep the screen awake during active work: `adb shell svc power stayon true`.
  4. If Wi-Fi is unresponsive, plug a USB-C cable into the host iMac; ADB will enumerate instantly.

---

## 2. Touch Screen 100% Unresponsive (0 Touches Registered)
- **Check 1**: Look at `/data/vendor/iptsd.conf` for `Neutral`.
  - **Symptom**: If `Neutral = constant` or `NeutralValue = 0`, IPTsD fails to subtract the background capacitive baseline. The entire glass is treated as one giant noise blob and 0 contacts are produced.
  - **Fix**: Ensure `Neutral = mode` is set.
- **Check 2**: Look for conflicting `ithc` event nodes.
  - Run `./scripts/status.sh`.
  - If a raw `Intel Touch Host Controller` node is listed in `/dev/input/`, run `./scripts/restart_iptsd.sh`.

---

## 3. Touch Drags Drop Midway / Virtual Joystick Freezes
- **Symptom**: In games with virtual joysticks (e.g. *Play Together*), dragging stops or releases while the finger/thumb is still firmly on the glass.
- **Cause**:
  1. `OrientationThresholdMax` was exceeded during 360° thumb rotation, marking `stable = false` and dropping frames.
  2. Thumb flattened against the screen, exceeding `SizeMax` or `AspectMax`, triggering `Validator` to emit an explicit touch lift (`lift_multitouch`).
- **Fix**: Verify `/data/vendor/iptsd.conf` contains:
  ```ini
  [Contacts]
  PositionThresholdMin = 0.0
  PositionThresholdMax = 100.0
  OrientationThresholdMin = 0
  OrientationThresholdMax = 180
  SizeMin = 0.1
  SizeMax = 8.0
  AspectMin = 1.0
  AspectMax = 10.0
  ```

---

## 4. Facebook "Log in Disabled: Embedded browser disabled"
- **Symptom**: Tapping "Log in with Facebook" in games opens a browser tab with:
  *"For your account security, logging into Facebook from an embedded browser is disabled. To continue, download and log into the Facebook app on your device and try again."*
- **Cause**: Bliss OS default browser (Jellyfish) is a lightweight wrapper around `android.webkit.WebView`. Meta blocks OAuth logins inside WebViews.
- **Fix**:
  - Install the official **Facebook App** (`com.facebook.katana`) from Google Play Store and log in. Games will automatically use Native Single Sign-On (SSO) with one tap.
  - Alternatively, install **Google Chrome** and set it as Default Browser in Android Settings. Chrome supports Chrome Custom Tabs, which Facebook allows.

---

## 5. Physical Volume / Power Buttons Unresponsive
- **Cause**: Bliss OS init doesn't always bind `gpio-keys` if keylayout is missing.
- **Fix**: Ensure `/system/usr/keylayout/gpio-keys.kl` contains:
  ```
  key 116   POWER
  key 115   VOLUME_UP
  key 114   VOLUME_DOWN
  ```
  The ACPI device is `MSHW0040:00` handled by `soc_button_array`.

---

## 6. Tablet Sluggish / `df` Hangs / ADB Drops (cpuinfo Mount Explosion)
- **Symptoms**: `df` or anything reading `/proc/*/mounts` spins at 100% kernel CPU; ANRs; adb goes `offline`. `grep -c cpuinfo /proc/1/mounts` returns thousands (seen: 65,536).
- **Cause**: `app_process`-based tools run **as root from adb shell / init namespace** (`svc`, `monkey`, `uiautomator`) initialize the native bridge, which bind-mounts `/system/etc/cpuinfo.arm64.txt` over `/proc/cpuinfo`. The source lives on `/` (`shared:1`), so each new mount joins that peer group and propagates back onto the source path. The count goes 2n+1 per call. `connect.sh` used to call `svc power stayon true` on every connect.
- **Fix** (installed by `install.sh`): `/system/etc/init/cpuinfo_mount_fix.rc` bind-mounts the cpuinfo source files onto themselves as `private` and makes `/proc` `private` at `post-fs-data`. Verified: 5x `svc` + `monkey` + `uiautomator` add 0 mounts; ARM apps still get their own private ARM cpuinfo.
- **Check**: `adb shell "grep -E ' /proc | /system/etc/cpuinfo' /proc/1/mountinfo"` must show no `shared:` tag on these lines, and `grep -c cpuinfo /proc/1/mounts` should stay at 2.
- **Recovery if it recurs**: reboot (stacked mounts on `/proc/cpuinfo` cannot be unmounted while held open).

