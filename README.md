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
   - **Fix**: Custom `iptsd_runner` actively removes raw ITHC event nodes and runs a background watchdog so `EventHub` only ever binds to the multi-touch virtual digitizer.

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

---

## Repository Contents

```
├── README.md
├── install.sh                  # One-step automated ADB installer
└── configs/
    ├── iptsd.conf              # Tuned IPTSD configuration
    ├── iptsd_runner            # Watchdog & raw ITHC cleanup launcher
    └── idc/
        ├── IPTSD_Virtual_Touchscreen_045E_0C1A.idc
        └── Vendor_045e_Product_0c1a.idc
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

---

## License
MIT
