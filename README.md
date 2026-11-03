# Surface Pro 7+ Touch & Multitouch Fix for Bliss OS / Android-x86

Tested and verified on **Microsoft Surface Pro 7+** running **Bliss OS 16.9.7** (Surface Edition).

---

## Target Machine & System Profile

| Specification | Value |
| :--- | :--- |
| **Device Model** | **Microsoft Surface Pro 7+** (Model 1960 / 1961) |
| **Manufacturer** | Microsoft Corporation |
| **Processor** | 11th Gen Intel(R) Core(TM) i3-1115G4 @ 3.00GHz (Tiger Lake, Iris Xe Graphics) |
| **Touch Controller** | Intel Touch Host Controller (`ithc` / `iptsd`, USB/HID ID: `045E:0C1A`) |
| **OS Distribution** | **Bliss OS 16.9.7** (Surface Edition, Codename: *Typhoon*) |
| **Bliss Build ID** | `Bliss-Surface-v16.9.7-x86_64-OFFICIAL-gapps-20241012` |
| **Android Version** | **Android 13** (API level 33, Build: `TQ3A.230901.001.C1`) |
| **Linux Kernel** | `6.1.112-gloria-surface-xanmod1` (Linux-Surface kernel with XanMod) |

---

## Problems Solved

1. **Dual Device Conflict (Touchscreen treated as single-touch mouse/pointer)**:
   - Linux kernel module `ithc` exposes raw single-touch legacy pointer nodes (`/dev/input/event*`), while userspace daemon `iptsd` creates `/dev/input/event*` (*IPTSD Virtual Touchscreen*).
   - Android's `EventHub` opened both simultaneously, causing single-touch pointer lockups.
   - **Fix**: Custom `iptsd_runner` actively removes raw ITHC event nodes and runs an event-driven (`inotifyd`) watchdog so `EventHub` only ever binds to the multi-touch virtual digitizer. Re-created nodes (e.g. after sleep/wake) are removed in ~5 ms.

2. **180° Flipped Orientation**:
   - Surface Pro digitizers have physically inverted hardware coordinates.
   - **Fix**: `InvertX = true` and `InvertY = true` in `iptsd.conf` and `surface-pro-7+.conf`.

3. **Touch Drops Mid-Drag / Virtual Joystick Freezes**:
   - In games with virtual joysticks (e.g. *Play Together*, *Roblox*, *Genshin Impact*, *Wild Rift*), rotating a thumb around the joystick causes rapid orientation and contact size changes.
   - By default in `iptsd`:
     - Orientation deltas exceeding `OrientationThresholdMax` marked the contact unstable and **dropped frames** (`continue;`).
     - Thumb contact size flattening exceeding `SizeMax` or `AspectMax` caused the `Validator` to emit an explicit touch lift (`lift_multitouch`), releasing the joystick while your finger was still on the glass.
     - Micro-movements smaller than `PositionThresholdMin` froze the touch coordinates to `last.mean`.
   - **Fix**: Expanded stability thresholds to allow full 360° rotation (`OrientationThresholdMax = 180`), zero deadzones (`PositionThresholdMin = 0.0`), and wide contact retention (`SizeMax = 8.0`, `AspectMax = 10.0`).

4. **Capacitive Centroid Jitter**:
   - Setting deactivation thresholds too low allows electrical background noise into the contact cluster, causing cursor wobble.
   - **Fix**: Balanced `ActivationThreshold = 24`, `DeactivationThreshold = 20`, and `Neutral = mode` for accurate capacitive baseline subtraction.

5. **Touch Watchdog CPU Drain & Touch Latency Under Load**:
   - The original watchdog rescanned all input nodes every 2 s, forking ~90 processes per pass (~7% of a CPU core around the clock, 115x more CPU than `iptsd` itself).
   - `iptsd` ran at normal priority, competing with game threads.
   - **Fix**: Event-driven watchdog (`inotifyd`, ~60x less CPU: 0.07 s/min) and `iptsd` started at nice `-8`, the same "urgent display" priority as Android's `InputReader`.

6. **System Stalls / `df` Hangs / ADB Drops (cpuinfo Mount Explosion)**:
   - Root `app_process` tools (`svc`, `monkey`, `uiautomator`) make the ARM native bridge bind-mount `cpuinfo.arm64.txt` over `/proc/cpuinfo`. Shared mount propagation doubled the mounts on every call (seen: 65,621 mounts). `connect.sh` triggered it via `svc power stayon true`.
   - **Fix**: `cpuinfo_mount_fix.rc` makes `/proc` and the cpuinfo source files private mounts at boot; `connect.sh` now uses `settings` instead of `svc`. Mount count stays at 2 after repeated tool calls.

> Full before/after values for every change: [`docs/CHANGELOG.md`](docs/CHANGELOG.md).

---

## Repository Contents

```
├── README.md
├── CLAUDE.md                   # Workspace guide & system invariants (Claude Code)
├── install.sh                  # One-step automated ADB installer
├── configs/
│   ├── iptsd.conf              # Tuned IPTSD configuration
│   ├── iptsd_runner            # Raw ITHC cleanup, event-driven watchdog, iptsd launcher (nice -8)
│   ├── init/
│   │   └── cpuinfo_mount_fix.rc  # Boot fix for the cpuinfo mount explosion
│   └── idc/
│       ├── IPTSD_Virtual_Touchscreen_045E_0C1A.idc
│       └── Vendor_045e_Product_0c1a.idc
├── scripts/
│   ├── connect.sh              # Reconnect Wi-Fi/USB ADB, adb root, keep screen on
│   ├── status.sh               # IPTSD / EventHub / battery diagnostics
│   ├── restart_iptsd.sh        # Restart touch daemon safely
│   ├── screencap.sh            # Pull a screenshot to the host
│   ├── pull_backup.sh          # Back up device configs to backups/
│   └── cpu_profile.sh          # CPU profile: gaming | balance | battery
└── docs/
    ├── ARCHITECTURE.md         # Input pipeline & watchdog internals
    ├── CHANGELOG.md            # Every change, with old and new values
    ├── COMMANDS.md             # Command cheatsheet
    ├── HARDWARE_SPECS.md       # DMI / PCI / ACPI details
    ├── TROUBLESHOOTING.md      # Known problems & fixes
    └── CAMERA.md               # Camera (IPU6) status: unsupported
```

---

## Quick Install (via ADB)

### Prerequisites
- Enable Developer Options and USB / Network Debugging on your Bliss OS tablet.
- Connect your PC to the tablet via Wi-Fi (`adb connect <TABLET_IP>:5555`) or USB-C.

### Installation
Run the installer:
```bash
git clone https://github.com/cfwork9601/surface-pro-7-plus-touch-blissos.git
cd surface-pro-7-plus-touch-blissos
chmod +x install.sh
./install.sh <TABLET_IP:5555 or SERIAL>
```
*(If only one device is connected to ADB, you can simply run `./install.sh`)*.

`install.sh` remounts the (read-only) root filesystem as read-write, deploys the touch configs, runner and IDC files, installs `cpuinfo_mount_fix.rc` (active from the next reboot), restarts `iptsd` and syncs.

### Helper Scripts
```bash
./scripts/connect.sh                       # Reconnect and get adb root
./scripts/status.sh                        # Touch / battery diagnostics
./scripts/cpu_profile.sh gaming            # Max performance (resets on reboot)
./scripts/cpu_profile.sh battery           # Longer battery life
./scripts/cpu_profile.sh balance           # Default
```

> **Do not run `svc`, `monkey` or `uiautomator` as root over adb** on a tablet without `cpuinfo_mount_fix.rc`: each call doubles the `/proc/cpuinfo` mounts. Use `settings`, `cmd` or `am start -n` instead.

---

## Detailed Configuration Breakdown

### 1. `configs/iptsd.conf`
Installed to `/data/vendor/iptsd.conf` and `/vendor/etc/iptsd.conf`:
```ini
[Config]
InvertX = true
InvertY = true
Width = 25.98
Height = 17.32

[Touchscreen]
Disable = false
DisableOnPalm = false
DisableOnStylus = false
Overshoot = 1.0

[Touchpad]
Disable = false
DisableOnPalm = false
Overshoot = 1.0

[Contacts]
Neutral = mode
NeutralValue = 0
ActivationThreshold = 24
DeactivationThreshold = 20
SizeThresholdMin = 0.0
SizeThresholdMax = 50.0
PositionThresholdMin = 0.0
PositionThresholdMax = 100.0
OrientationThresholdMin = 0
OrientationThresholdMax = 180
SizeMin = 0.1
SizeMax = 8.0
AspectMin = 1.0
AspectMax = 10.0
```

### 2. `configs/idc/*.idc`
Installed to `/system/usr/idc/` and `/data/system/devices/idc/`:
```properties
# Input device config file for Surface Pro 7+ IPTSD Virtual Touchscreen
device.internal = 1
touch.deviceType = touchScreen
touch.orientationAware = 1
touch.gestureMode = default
touch.size.calibration = none
touch.pressure.calibration = none
touch.orientation.calibration = none
touch.distance.calibration = none
```

### 3. `configs/iptsd_runner`
Installed to `/system/vendor/bin/iptsd_runner` (started by Bliss `init.sh` as service `iptsd_runner`):
1. Removes raw `Intel Touch Host Controller` input nodes (event2–9) using shell builtins only.
2. Event-driven watchdog: `inotifyd - /dev/input:nn` (create events only; this toybox ignores the first mask letter) removes re-created raw nodes in ~5 ms.
3. 60 s safety-net rescan.
4. `exec nice -n -8 /vendor/bin/iptsd /dev/hidrawN`.

### 4. `configs/init/cpuinfo_mount_fix.rc`
Installed to `/system/etc/init/`. Runs at `post-fs-data`, before zygote:
```
on post-fs-data
    mount none /system/etc/cpuinfo.arm64.txt /system/etc/cpuinfo.arm64.txt bind
    mount none none /system/etc/cpuinfo.arm64.txt private
    mount none /system/etc/cpuinfo.arm.txt /system/etc/cpuinfo.arm.txt bind
    mount none none /system/etc/cpuinfo.arm.txt private
    mount none none /proc private
```
Health check: `adb shell grep -c cpuinfo /proc/1/mounts` → `2`.

---

## Other Tablet Tweaks (applied on the device, not by `install.sh`)

| Tweak | Old | New |
| :--- | :--- | :--- |
| Battery % in status bar (`status_bar_show_battery_percent`) | hidden unless charging | `2` (always, next to icon) |
| Animation scales (window / transition / animator) | `1.0` | `0.5` |
| SmartDock (`cu.axel.smartdock`) | installed, crash-looping | removed for user 0 |
| 64 GB microSD | portable exFAT | adopted internal storage (encrypted ext4) |

Details, commands and how to revert each one: [`docs/CHANGELOG.md`](docs/CHANGELOG.md).

---

## License
MIT
