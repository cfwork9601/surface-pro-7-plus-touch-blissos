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

---

## 7. App on SD Card Says "No Internet" / "Failed to Connect" (Other Apps Work)
- **Symptoms**: Apps moved to the adopted SD card can't connect after a reboot (e.g. Fruit Ninja `ReliableTimeFailed`); apps on internal storage work.
- **Cause**: Restricted networking mode (`restricted_networking_mode = 1`) allowlist is built at boot before the SD card mounts, so SD apps are left out (no `RESTRICTED_MATCH` in the BPF uid owner map).
- **Fix** (installed by `install.sh`): `sd_app_network_fix` boot service rebuilds the allowlist once the SD apps are available. Log: `adb shell logcat -d -s sd_app_network_fix`.
- **Manual fix**: `adb shell "settings put global restricted_networking_mode 0; sleep 1; settings put global restricted_networking_mode 1"`
- **Check an app**: get its uid with `adb shell pm list packages -U <pkg>`, then `adb shell "dumpsys connectivity trafficcontroller | grep -E '^ *<uid> '"` must show `RESTRICTED_MATCH`.
- **Not every "Connection Error" is this.** If the uid already shows `RESTRICTED_MATCH` and `dumpsys netpolicy` shows `effective=NONE` for it, the network is not blocked. Example: Pixel Gun 3D (`com.pixel.gun3d`) reaches its CDN and Firebase, but its `auth_v2` login fails right after a Play Integrity token request. It fails the same way from internal storage (tested 2026-11-06), so the likely cause is Bliss OS failing Play Integrity, not the SD card.

## 8. Touch Dead After Running an `iptsd-*` Tool (Controller Hung / Single-Touch Mode)
- **Symptom**: touch stops right after running `iptsd-dump`, `iptsd-check-device`, `iptsd-calibrate` or similar while `iptsd` was running. `iptsd` may still be listed, or `./scripts/restart_iptsd.sh` shows no `iptsd` process and `getprop init.svc.iptsd_runner` says `restarting`.
- **Cause**: these tools open the same hidraw node `iptsd` is streaming from.
  - `iptsd-dump` (and anything built on the iptsd `Runner`) switches the digitizer back to **single-touch mode** when it exits, so `iptsd` stops receiving heatmaps.
  - `iptsd-check-device` sends a feature-report request (`HIDIOCGFEATURE`). Sent while `iptsd` is streaming, it can time out (`IOCTL ... failed: Connection timed out`) and leave the ITHC controller **hung**. `iptsd_runner` runs the same check before starting `iptsd`, so the daemon never comes back.
- **Diagnose**: `adb shell /vendor/bin/iptsd-check-device <node>` (only after `iptsd` is down). A timeout means the controller is hung.
- **Fix**:
  1. Single-touch mode only (check passes): `./scripts/restart_iptsd.sh`.
  2. Controller hung (check times out): reset the ITHC driver, then restart `iptsd`:
     ```bash
     adb shell 'd=$(basename $(ls -d /sys/bus/pci/drivers/ithc/0000:*)); echo $d > /sys/bus/pci/drivers/ithc/unbind; sleep 2; echo $d > /sys/bus/pci/drivers/ithc/bind'
     ./scripts/restart_iptsd.sh
     ```
     The ITHC raw input node reappears after the rebind; the `iptsd_runner` watchdog removes it automatically. A reboot also works.
- **Prevention**: never run `iptsd-*` helper tools against the touch controller while `iptsd` is running. Find nodes with the read-only commands in `docs/COMMANDS.md` §2. For a raw capture, run `iptsd-dump`, then always `./scripts/restart_iptsd.sh`.
