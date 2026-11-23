# Changelog: Tablet & Repository Changes

Every change made to the Surface Pro 7+ (Bliss OS 16.9.7) and this repository, with the **old** and **new** value for each, so any change can be checked or reverted.

---

## 2026-11-22

### 0. Boot switch buttons: Bliss → Windows and Windows → Bliss

| | Old | New |
|---|---|---|
| Bliss → Windows | Reboot, pick Windows in GRUB | **"Boot to Windows" app + "Windows" Quick Settings tile** (`bootswitch-app/`, package `dev.surface.bootswitch`) runs `/system/etc/boot_to_windows.sh` as root (KernelSU `su`) |
| Windows → Bliss | Restart (BlissOS is first in BootOrder) | **"Boot to Bliss" shortcut** (Desktop + Start menu), installed by `windows/Install-BootToBliss.ps1` |
| UEFI BootOrder / GRUB default | `0005 BlissOS, 0004 Windows Boot Manager, …` / BlissOS | unchanged |

- Both buttons are one-shot: Bliss sets UEFI `BootNext` to the "Windows Boot Manager" entry; Windows sets `{fwbootmgr} bootsequence` to the "BlissOS" entry. Entries are looked up by name, not number.
- `efivarfs` is not mounted on Bliss by default; the script mounts it. A write must be one `write()` of the full 6 bytes (attributes `07 00 00 00` + entry number LE), so the script uses `dd`, not `printf` straight into the file (EINVAL).
- The app needs root: KernelSU app → Superuser → enable "Boot to Windows". Without it the app shows an error and does nothing.
- Windows setup (once, admin PowerShell): `powershell -ExecutionPolicy Bypass -File .\Install-BootToBliss.ps1`. It registers a "Boot to Bliss" scheduled task with highest privileges so clicks don't prompt for UAC.
- Caveat: GRUB uses `savedefault`. If you ever pick Windows manually in the GRUB menu, GRUB's default becomes Windows, and "Boot to Bliss" will land in GRUB's 5 s countdown to Windows. Pick BlissOS once in GRUB to reset it.
- Test without rebooting: `adb shell su -c "/system/etc/boot_to_windows.sh --no-reboot"` then `--clear`.
- Revert: `adb uninstall dev.surface.bootswitch; adb shell 'mount -o remount,rw /; rm /system/etc/boot_to_windows.sh; sync'`; on Windows run the installer with `-Uninstall`.

### 1. UI smoothness: render resolution + GPU minimum clock

Touch input itself was healthy (100 Hz, no gaps on normal drags). The stutter came from frames missing the 60 Hz deadline in every app, including plain Settings.

| | Old | New |
|---|---|---|
| Render size (`wm size` / `wm density`) | 2736x1824 / 320 | **2052x1368 / 240** (same physical UI size, about 44% fewer pixels) |
| GPU min clock (`/sys/class/drm/card0/gt_min_freq_mhz`) | 100 MHz | **600 MHz** (set at boot by `configs/init/gpu_min_freq.rc`) |
| HWUI renderer | `skiagl` | `skiagl` (unchanged; Vulkan tested and rejected) |
| CPU profile | `balance` | `balance` (unchanged; `gaming` tested, no gain) |

- Measured with `dumpsys gfxinfo` on a scripted Settings scroll (`cmd input swipe`, 12 up/down pairs):

  | Setup | Median | p90 | p99 |
  |---|---|---|---|
  | GPU min 100 MHz | 14–27 ms | 28–30 ms | 32 ms |
  | **GPU min 600 MHz** | **11 ms** | **12 ms** | **13 ms** |
  | GPU min 600 + CPU `gaming` | 14 ms | 15 ms | 17 ms |

- Lower resolution in Termius (normal use): late frames 20% → 7.5%, p90 53 → 26 ms.
- Vulkan (`setprop debug.hwui.renderer skiavk`) was much worse in Termius: median 17 ms, p90 85 ms, p99 400 ms. Do not enable.
- The `wm size`/`wm density` overrides persist by themselves (`settings global display_size_forced`).
- Revert: `adb shell wm size reset; adb shell wm density reset`; `adb shell 'mount -o remount,rw /; rm /system/etc/init/gpu_min_freq.rc; echo 100 > /sys/class/drm/card0/gt_min_freq_mhz; sync'`.

### 1b. Boot logo off-centre after the render-size change

The boot animation starts (~7 s) at the full 2736x1824 before `system_server` applies the `wm size` override, so the logo shifted off-centre when the override kicked in.

| | Old | New |
|---|---|---|
| `ro.surface_flinger.max_graphics_width` / `_height` (`/system/build.prop`) | unset | **2052 / 1368** |
| `wm size` / `wm density` | 2052x1368 / 240 | 2052x1368 / 240 (unchanged; still needed so apps draw at 2052x1368) |

- Fix confirmed on device: the logo stays centred for the whole boot.
- `dumpsys display` still reports `real 2736 x 1824` (the panel); that is expected.
- Original `build.prop` backed up to `backups/<timestamp>/system_build.prop` and `/data/local/tmp/build.prop.bak` on the tablet.
- Revert: `adb shell 'mount -o remount,rw /; sed -i -e "/max_graphics_/d" -e "/Render at 2052x1368/d" /system/build.prop; sync'`, then reboot.

### 2. Background apps restricted, Google app removed (tablet only)

| | Old | New |
|---|---|---|
| Google app, Play Store, Facebook, Instagram, Roblox, YouTube, Brave, Chrome, Gmail, WhatsApp | Free to run in background | `RUN_ANY_IN_BACKGROUND ignore` (+ `restricted` standby bucket where Android allows it) |
| Google app (`com.google.android.googlequicksearchbox`) | Installed, default assistant | Uninstalled for user 0; `assistant` setting cleared (voice recognition stays Claude) |

- Why: those apps held 250–540 MB each and caused memory-compaction spikes (`kcompactd0` at 57% CPU) that dropped frames.
- Gmail and WhatsApp no longer notify until opened.
- Revert one app: `adb shell cmd appops set <pkg> RUN_ANY_IN_BACKGROUND allow; adb shell am set-standby-bucket <pkg> active`. Restore Google app: `adb shell cmd package install-existing com.google.android.googlequicksearchbox`.

### 3. Warning: `iptsd-dump` kills touch on exit

`iptsd-dump` (iptsd v3.x) switches the digitizer back to **single-touch mode** when it exits (`core/linux/runner.hpp`: `set_mode(Singletouch)`), so the running `iptsd` stops receiving heatmaps and touch goes dead. Always run `./scripts/restart_iptsd.sh` after a raw capture.

### 4. Touch detection threshold: fix breaks on fast flicks

| | Old | New |
|---|---|---|
| `ActivationThreshold` (`/data/vendor/iptsd.conf`) | 24 | **16** |
| `DeactivationThreshold` | 20 | **13** |

- Symptom: during fast back-and-forth flicks, about one touch break per 10–20 s. Android saw a lift and a new touch 10–40 ms later, which ended drags and scrolls early.
- Diagnosis: 22 s raw capture (`iptsd-dump`) replayed offline through iptsd **v3** (the version on the tablet), built in a Fedora container with a small replay tool that prints every frame's contacts and heatmap. The replay reproduced both live breaks exactly. No contact was marked unstable or invalid; the finger was missing at **detection**:
  - Break 1 (1 frame): strong finger (peak 119 vs background 75) split across 4 sensor cells; blurred peak ≈ 22–23 < 24.
  - Break 2 (4 frames): finger pressure lightened at the flick turnaround (peak 103–115) while nearly stationary.
- Threshold sweep on the same recording (breaks / ghost contacts): 24 → 2 / 0, 20 → 1 / 0, **16 → 1 (1 frame) / 0**, 12 → 0 / 0. Picked 16 to keep margin for charger noise. Touches start/end about 1 frame (10 ms) later.
- An earlier test lowering only `DeactivationThreshold` (20 → 16) did nothing, as expected: it does not affect whether a finger is detected.
- Live check after the change, on the charger: 0 breaks, 0 ghost or very short touches, one finger slot used (short sample).
- Revert: set both values back to 24 / 20 in `/data/vendor/iptsd.conf` (backup on the tablet: `/data/vendor/iptsd.conf.bak-act24`), then `./scripts/restart_iptsd.sh`.

---

## 2026-11-20

### 1. Multi-finger touchpad gestures (Type Cover) + settings app

| | Old | New |
|---|---|---|
| 3-finger swipe up | Nothing (Android 13 has no touchpad gestures) | Recents (default) |
| 4-finger swipe up | Nothing | Home (default) |
| Other swipes (3/4 fingers, down/left/right) | Nothing | Configurable in the app (default: nothing) |

- Why custom: Android 13's touchpad path is the old `TouchInputMapper` (POINTER mode). The gestures library / `TouchpadInputMapper` only arrived in Android 14 and is absent from `libinputreader.so`.
- Daemon: `configs/touchpad_gestures.sh` → `/system/etc/touchpad_gestures.sh`, started by `configs/init/touchpad_gestures.rc` (on `sys.boot_completed=1`). Pipeline: `getevent` on the touchpad (passive, no grab) → `awk` prints `<fingers> <dx> <dy>` when all fingers lift after a swipe with 3 or more fingers → shell loop reads the config, picks the direction (it must cover the threshold distance and be mostly along one axis), and runs the action through `cmd input` / `cmd statusbar`. Both are native binder calls, not `app_process`, so invariant #6 still holds. Zero CPU when the touchpad is idle. Re-finds the touchpad when the Type Cover is detached or reattached.
- Settings app: `gesture-app/` (Kotlin + Jetpack Compose + Material 3, package `dev.surface.touchpadgestures`). It has an on/off switch, an action for each 3/4-finger × up/down/left/right swipe, a swipe distance setting (5–25 mm, default 10), live "last gesture" status, and a Quick Settings tile to toggle gestures. It writes `/data/user/0/dev.surface.touchpadgestures/files/gestures.conf` (key=value). The daemon reads that file on every gesture using shell built-ins only, with no `eval`, and only accepts whitelisted keys and values. The daemon writes `files/status` back for the app to display.
- Actions: home, back, recents, last_app (quick switch: two Recents presses, the same as a swipe along the bottom bar; handles split-screen and web apps), notifications, quick_settings, close_panels, screenshot (`KEYCODE_SYSRQ`), play_pause, next_track, prev_track.
- Build: toolchain in `~/opt` on the iMac (`jdk17`, `android-sdk`, `gradle-8.9`; about 1 GB). `cd gesture-app && JAVA_HOME=~/opt/jdk17 ./gradlew assembleDebug`. `install.sh` installs the APK if it has been built.
- Restart the daemon: `./scripts/restart_gestures.sh`. Logs: `adb shell logcat -s touchpad_gestures`.
- Known limitation: Android still sees the fingers, so a swipe may also scroll the app under the pointer a little.
- **Direction scaling (same day).** The touchpad is about 98 × 50 mm (ABS max 1956 × 997), so up/down swipes with 3–4 fingers only travel about 10–15 mm and were rejected when the distance setting was 17–20 mm (confirmed from the log). Vertical travel is now scaled by `PAD_W/PAD_H` before it is compared, so the setting applies as-is left/right and at about half up/down (the app shows both values). Rejected swipes are now logged with their measured dx/dy, and the app's status card shows them too.
- **Fix (same day): gestures stopped after the Type Cover re-enumerated (sleep/resume, fold, reattach).** The kernel deletes and recreates the touchpad node, but `getevent` does not exit on a deleted node: it kept the stale fd and spun at **100% of one CPU core** reading nothing. The daemon now runs an `inotifyd /dev/input:nnd` watchdog (same pattern as `iptsd_runner`) that kills the reader (its PID is kept in `/dev/touchpad_gestures/getevent.pid`) when the node is deleted or a new touchpad node appears, and the main loop reopens the current node. Verified by deleting the node and re-adding it through ueventd (`echo add > /sys/class/input/event26/uevent`): the reader reopened it within seconds and used 0 CPU while idle.
- Revert: `adb uninstall dev.surface.touchpadgestures; adb shell 'mount -o remount,rw /; rm /system/etc/init/touchpad_gestures.rc /system/etc/touchpad_gestures.sh; sync'`, then reboot.

---

## 2026-11-02

### Summary

| # | Area | Change | Where it lives |
|---|------|--------|----------------|
| 1 | Storage | 64 GB microSD adopted as internal storage | Tablet only |
| 2 | Storage | Fruit Ninja moved to SD; 14 apps precompiled so they can be moved | Tablet only |
| 3 | UI | Battery percentage always shown in status bar | Tablet only |
| 4 | System | **cpuinfo mount explosion fixed** (boot rc + `connect.sh`) | Repo + tablet |
| 5 | Apps | SmartDock (crash-looping) removed for user 0 | Tablet only |
| 6 | UI | Animation scale 1.0x → 0.5x | Tablet only |
| 7 | CPU | `scripts/cpu_profile.sh` added (gaming / balance / battery) | Repo |
| 8 | Touch | **Watchdog made event-driven** (`inotifyd`) | Repo + tablet |
| 9 | Touch | **`iptsd` priority raised** to nice -8 | Repo + tablet |
| 10 | Docs | `CLAUDE.md` rootfs note corrected, new invariant #6 | Repo |
| 11 | Network | **Apps on SD card had no internet**: boot service re-allowlists them | Repo + tablet |
| 12 | Camera | USB webcam path verified; workarounds documented | Docs (+ `uvcvideo` loaded once, not persistent) |

---

### 1. MicroSD card adopted as internal storage

| | Old | New |
|---|---|---|
| Mode | Portable (`public:8,1`), exFAT, label `android` | Adopted (`private:8,2`), encrypted ext4 |
| Mount | `/mnt/media_rw/6AFF-F5F3` | `/mnt/expand/14a62407-55be-4b7b-8ac7-f958e8d6260e` |
| Usable size | 58 GB | 56 GB |

- Command: `adb shell sm partition disk:8,0 private` (wipes the card).
- The only file on the card, `1 2 3 4 Player Games [3.3.2].zip` (122 MB), was copied to internal `Download/` first and checksum-verified (md5 `2141250864215ea73713859ee6ac8bad`).
- Encryption key: `/data/misc/vold/expand_16cbcecea78a4ff29840c8157115c6ba.key`. **If `/data` is wiped, the card is unreadable and must be re-formatted.**
- Reader: built-in microSD slot is USB-attached (`Generic- SD/MMC`), shows as `sda`.
- Revert: Settings → Storage → SD card → Format as portable (wipes card).

### 2. Moving apps to the SD card ("not enough storage" error)

- **Cause:** Settings shows "not enough storage" for every move failure. The real error was `Move only supported for modern cluster style installs` (status `-6`): Android 13 only moves apps whose install dir has an `oat/` subfolder.
- **Fix:** precompile to create `oat/`, then move:
  ```bash
  adb shell cmd package compile -m speed-profile -f <package>
  adb shell pm move-package <package> 14a62407-55be-4b7b-8ac7-f958e8d6260e
  ```
- Moved: `com.halfbrick.fruitninjafree` (~530 MB) → SD card.
- Precompiled (now movable from Settings, **not** moved): WhatsApp, YouTube, Chrome, FourPlayers, Gboard, Gemini, Claude, TwoPlayerGamesChallenge, X-plore, Roblox, Papergames, ibisPaint X, Sketchbook, Facebook.

### 3. Battery percentage in status bar

| Setting | Old | New |
|---|---|---|
| `system status_bar_show_battery_percent` | `null` (shown only while charging) | `2` (next to icon, always) |

- Settings has no toggle on this build: `android:bool/config_battery_percentage_setting_available = false`.
- Values: `0` hidden, `1` inside icon (hard to read), `2` next to icon.
- Revert: `adb shell settings put system status_bar_show_battery_percent 0`

### 4. cpuinfo mount explosion (system stalls, `df` hangs, adb drops)

**Symptoms:** after ~2 h, `/proc/1/mounts` had **65,621** entries (32,768 on `/proc/cpuinfo` + 32,767 on `/system/etc/cpuinfo.arm64.txt`; kernel limit `fs.mount-max = 100000`). Anything that read the mount table (`df`, vold, app launch) spun in the kernel for 100+ s. Caused ANRs (X-plore), high load and an adb `offline` drop.

**Root cause:** `app_process`-based tools run **as root** from adb shell / the init mount namespace (`svc`, `monkey`, `uiautomator`) initialise the native bridge (`libndk_translation`), which bind-mounts `/system/etc/cpuinfo.arm64.txt` over `/proc/cpuinfo`. The source is on `/` (`shared:1`), so each new mount joins that peer group and propagates back onto the source path. Count per call goes 2n+1 (measured: 3 → 7 → 15 → 31). `scripts/connect.sh` ran `svc power stayon true` on every connect. Normal apps are not affected (zygote's namespace is a `master:1` slave, and the mount fails with `EPERM` there).

**Fix A: `scripts/connect.sh`**

| Old | New |
|---|---|
| `svc power stayon true` | `settings put global stay_on_while_plugged_in 7` (same setting, via native `cmd settings`) |

**Fix B: new `configs/init/cpuinfo_mount_fix.rc`** → `/system/etc/init/cpuinfo_mount_fix.rc` (installed by `install.sh`):
```
on post-fs-data
    mount none /system/etc/cpuinfo.arm64.txt /system/etc/cpuinfo.arm64.txt bind
    mount none none /system/etc/cpuinfo.arm64.txt private
    mount none /system/etc/cpuinfo.arm.txt /system/etc/cpuinfo.arm.txt bind
    mount none none /system/etc/cpuinfo.arm.txt private
    mount none none /proc private
```

| Mount (init namespace) | Old propagation | New propagation |
|---|---|---|
| `/proc` | `shared:7` | private |
| `/system/etc/cpuinfo.arm64.txt` | part of `/` (`shared:1`) | own private bind mount |
| `/system/etc/cpuinfo.arm.txt` | part of `/` (`shared:1`) | own private bind mount |

**Verified after reboot:** 5x `svc` + `monkey` + `uiautomator` → cpuinfo mounts stay at **2**, total 88 mounts. Shell `/proc/cpuinfo` shows the real Intel CPU again (the leak had shown ARM). ARM apps (Fruit Ninja, Roblox) still start and get their own private ARM cpuinfo.

- Health check: `adb shell grep -c cpuinfo /proc/1/mounts` → should be `2`.
- Revert: `adb shell "mount -o remount,rw / && rm /system/etc/init/cpuinfo_mount_fix.rc && sync"`, reboot.

### 5. SmartDock removed

| | Old | New |
|---|---|---|
| `cu.axel.smartdock` (system app, `/system/system_ext/priv-app/smart-dock`) | Installed, crash-looping (9 crashes/day) | Uninstalled for user 0 |

- Crash: `BadTokenException ... permission denied for window type 2038` (`SYSTEM_ALERT_WINDOW: deny`). Not used (home = Launcher3).
- Revert: `adb shell cmd package install-existing cu.axel.smartdock`

### 6. Animation speed

| Setting (`global`) | Old | New |
|---|---|---|
| `window_animation_scale` | `1.0` | `0.5` |
| `transition_animation_scale` | `1.0` | `0.5` |
| `animator_duration_scale` | `1.0` | `0.5` |

- Revert: set all three back to `1.0`.

### 7. CPU power profiles: new `scripts/cpu_profile.sh`

| Profile | Governor | EPP |
|---|---|---|
| `balance` (boot default, unchanged) | `powersave` | `balance_performance` |
| `gaming` | `performance` | `performance` |
| `battery` | `powersave` | `balance_power` |

- Not persistent: a reboot always returns to `balance`. Run with no argument to show the current profile.

### 8. Touch watchdog: polling → event-driven

**Old `configs/iptsd_runner` (watchdog part):**
```sh
cleanup_raw_ithc() {
    for namefile in /sys/class/input/event*/device/name; do
        if [ -f "$namefile" ]; then
            case "$(cat "$namefile" 2>/dev/null)" in
                *"Intel Touch Host Controller"*)
                    evnode="/dev/input/$(basename $(dirname $(dirname "$namefile")))"
                    if [ -e "$evnode" ]; then
                        rm -f "$evnode" 2>/dev/null
                    fi
                    ;;
            esac
        fi
    done
}
cleanup_raw_ithc
(
    while true; do
        cleanup_raw_ithc
        sleep 2
    done
) &
```

**New:**
```sh
remove_if_ithc() {            # $1 = "eventN"; shell builtins only, no forks
    case "$1" in event*) ;; *) return ;; esac
    namefile="/sys/class/input/$1/device/name"
    [ -r "$namefile" ] || return
    read -r devname < "$namefile"
    case "$devname" in
        *"Intel Touch Host Controller"*)
            [ -e "/dev/input/$1" ] && rm -f "/dev/input/$1" 2>/dev/null ;;
    esac
}
cleanup_raw_ithc() { for sysnode in /sys/class/input/event*; do remove_if_ithc "${sysnode##*/}"; done; }
cleanup_raw_ithc
(   # react to node creation instantly
    while true; do
        cleanup_raw_ithc
        inotifyd - /dev/input:nn | while read -r _event _dir node; do remove_if_ithc "$node"; done
        sleep 5
    done
) &
(   # safety net
    while true; do sleep 60; cleanup_raw_ithc; done
) &
```

| Metric | Old | New |
|---|---|---|
| Mechanism | Rescan all 22 input nodes every 2 s, ~90 forks per pass | `inotifyd` create events + 60 s safety rescan |
| Touch pipeline CPU | 21.0 s in first 287 s of uptime (~7% of a core, ~4.4 s/min) | **0.07 s/min** (~60x less) |
| Raw ITHC node removal latency | up to 2 s | **~5 ms** (measured) |
| Sleep/wake | works | works (verified by user) |

- Toybox quirk: this `inotifyd` ignores the first mask letter. `:nn` = create-only; `:n` fails with `Invalid argument`; the default mask reports every read of every input node (a flood on each touch frame).

### 9. `iptsd` process priority

| | Old | New |
|---|---|---|
| Launch | `exec /vendor/bin/iptsd "$dev"` | `exec nice -n -8 /vendor/bin/iptsd "$dev"` |
| Nice value | `0` (same as games) | `-8` (Android "urgent display", same as `InputReader`) |

- Watchdog subshells stay at nice 0. Not real-time scheduling.
- Revert (8 + 9): a backup of the old runner is on the tablet at `/data/local/tmp/iptsd_runner.bak`, or check out `configs/iptsd_runner` from commit `304cffc` and run `./install.sh`.

### 10. Documentation

- `CLAUDE.md`: corrected "root filesystem is mounted `rw`" → boots **read-only**, `install.sh` remounts `rw`. Added invariant #6 (no root `svc`/`monkey`/`uiautomator`; keep the cpuinfo fix). Updated invariant #1 for the new watchdog. Added `cpu_profile.sh`.
- `docs/TROUBLESHOOTING.md`: §6 cpuinfo mount explosion.
- `docs/COMMANDS.md`: stay-awake via `settings`, battery percent, animations, CPU profiles, SD card app moves (§6).
- `docs/ARCHITECTURE.md`: new watchdog and priority description.
- `docs/CAMERA.md`: camera (IPU6) status, linked from `CLAUDE.md`.

### 11. Apps on the SD card have no internet ("Failed to connect", `ReliableTimeFailed`)

**Symptoms:** Fruit Ninja showed *Failed to connect to server... ReliableTimeFailed* while YouTube worked. In-app HTTPS failed in about 6 ms (`TRuntime.CctTransportBackend: Couldn't open connection`). Started after the app was moved to the SD card and the tablet rebooted.

**Root cause:** Bliss (Lineage-based) has **restricted networking mode** on (`settings global restricted_networking_mode = 1`; it powers the per-app "Network access" switch). Only uids with `RESTRICTED_MATCH` in netd's BPF uid owner map can use the network. NetworkPolicyManager builds that allowlist at boot, **before the adopted SD card is mounted**, so every app on the card is skipped and never re-added. Checked: all 9 SD apps had no `RESTRICTED_MATCH`; every internal app (YouTube, Roblox, WhatsApp, Chrome) had it.

| Apps on SD card | Old (after every boot) | New |
|---|---|---|
| Fruit Ninja, Honkai Impact 3rd, Prisma3D, Sketchbook, X-plore, Farm Heroes Saga, Facebook, FourPlayers, ibisPaint X | not allowlisted → no network | allowlisted ~30 s after boot |

**Fix:** new boot service (installed by `install.sh`):
- `configs/init/sd_app_network_fix.rc` → `/system/etc/init/`: oneshot service started on `sys.boot_completed=1`.
- `configs/sd_app_network_fix.sh` → `/system/etc/`: waits for the adopted volume and its packages, checks each SD app's uid for `RESTRICTED_MATCH`, and **only if any is missing** toggles `restricted_networking_mode` 1 → 0 → 1 so the allowlist is rebuilt. Does nothing if restricted mode is off. Logs to logcat tag `sd_app_network_fix`.
- Side effect: during the ~1 s toggle, apps you've blocked with "Network access" off are briefly not blocked. It happens only when SD apps are missing, i.e. once per boot.

**Verified after reboot:** log `not allowlisted: ... -> rebuilding restricted-mode allowlist`, then all SD apps have `RESTRICTED_MATCH`, mode back at `1`, Fruit Ninja connects (confirmed by user).

- Manual fix (same effect): `adb shell "settings put global restricted_networking_mode 0; sleep 1; settings put global restricted_networking_mode 1"`
- Check: `adb shell logcat -d -s sd_app_network_fix`
- Revert: `adb shell "mount -o remount,rw / && rm /system/etc/init/sd_app_network_fix.rc /system/etc/sd_app_network_fix.sh && sync"`
- Script note: mksh treats an unquoted `|` in `${var%%pattern}` as alternation; it must be quoted (`${line%%"|"*}`).

### 12. Camera workarounds

- Built-in cameras (IPU6) remain unsupported on kernel 6.1. See `docs/CAMERA.md`.
- Verified the USB webcam (UVC) path: `uvcvideo.ko` loads cleanly, the external camera HAL is running, and `android.hardware.camera.external` is declared.

| | Old | New |
|---|---|---|
| `uvcvideo` module | not loaded | loaded manually with `modprobe uvcvideo` (until next reboot; autoloads on UVC plug-in) |
| `docs/CAMERA.md` | status only | adds a Workarounds section: USB webcam, Android 14+ phone as USB webcam, app compatibility, verify commands |

