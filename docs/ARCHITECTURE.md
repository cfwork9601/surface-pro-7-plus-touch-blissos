# Touch & Input Subsystem Architecture

## Overview
On modern Intel-based Surface devices (e.g. Surface Pro 7+ with Tiger Lake), Microsoft replaced older SPI/I2C controllers with the Intel Touch Host Controller (ITHC) running over PCI (`00:10.6`).

Unlike standard touchscreens that emit processed coordinates from hardware, Surface devices transmit raw capacitive heatmap matrices to the OS.

```
+------------------------------------------------------------------------+
|                            PHYSICAL DIGITIZER                          |
|         (Raw Capacitive Heatmap Frames ~0-255, 120Hz/60Hz)             |
+------------------------------------------------------------------------+
                                    |
                                    v
+------------------------------------------------------------------------+
|                     KERNEL MODULE: ithc.ko                             |
|  - Manages DMA and ring buffers on Intel Touch Host Controller         |
|  - Exposes raw HID report stream at /dev/hidraw1                       |
|  - Exposes legacy pointer at /dev/input/event* (CONFLICT GENERATOR!)   |
+------------------------------------------------------------------------+
                                    |
                +-------------------+--------------------+
                |                                        |
                v                                        v
     [Raw /dev/input/event*]                   [/dev/hidraw1]
                |                                        |
    (ELIMINATED BY WATCHDOG!)                            v
                |                      +---------------------------------+
                |                      |    USERSPACE DAEMON: iptsd      |
                |                      |  - Subtracts Neutral mode baseline |
                |                      |  - Gaussian fitting & cluster span|
                |                      |  - Contact tracker & stabilizer |
                |                      +---------------------------------+
                |                                        |
                |                                        v
                |                            [Linux uinput subsystem]
                |                                        |
                +-------------------<--------------------+
                                    |
                                    v
       /dev/input/event14 ("IPTSD Virtual Touchscreen 045E:0C1A")
                                    |
                                    v
+------------------------------------------------------------------------+
|                     ANDROID EVENTHUB & INPUTREADER                     |
|  - Matches /system/usr/idc/Vendor_045e_Product_0c1a.idc               |
|  - Bypasses pointer / slop / pressure filtering (calibration = none)   |
|  - Dispatches MOTIONEVAL events to Android WindowManager & ViewRootImpl |
+------------------------------------------------------------------------+
```

---

## Key Subsystems

### 1. Dual Device Clash & The Watchdog
- **The Issue**: `ithc.ko` exposes a raw input event node identifying as `Intel Touch Host Controller`. Android's `EventHub` opens it as a single-touch mouse/pointer. If both are open, Android locks touch to a single coordinate.
- **The Fix**: `/system/vendor/bin/iptsd_runner` (source: `configs/iptsd_runner`):
  1. Runs an initial cleanup: for every `/sys/class/input/eventN`, reads `device/name` with the shell builtin `read` and deletes `/dev/input/eventN` if it contains `Intel Touch Host Controller`. ITHC exposes 8 such nodes (event2–9, including `... Stylus`).
  2. **Event-driven watchdog**: `inotifyd - /dev/input:nn` reports each node the kernel re-creates (resume from sleep, re-enumeration), and only that node is checked. Measured removal time: ~5 ms. The previous 2 s polling loop forked ~90 processes per pass and used ~7% of a core at all times.
     - Toybox quirk: this `inotifyd` ignores the first mask letter, so `:nn` = create-only. A plain `:n` fails with `Invalid argument`, and the default mask would report every read of every input node (a flood on each touch frame).
  3. A 60 s safety-net rescan in case an event is missed while `inotifyd` restarts.
  4. `exec nice -n -8 iptsd /dev/hidrawN`: touch processing runs at Android's "urgent display" priority (same as `InputReader`), so CPU-heavy games can't delay touch frames.

### 2. Coordinate Transformation (180° Inversion)
- Microsoft Surface digitizers are physically inverted.
- `InvertX = true` and `InvertY = true` in `/data/vendor/iptsd.conf` map physical digitizer pixels to landscape `ROTATION_0`.
- Android's `touch.orientationAware = 1` in the `.idc` file handles subsequent 90°/180°/270° display rotations seamlessly.

### 3. Contact Stability & Virtual Joystick Math
In `iptsd` C++ source:
- `PositionThresholdMin`: Sets minimum centimeters required before registering movement. Must be `0.0` for gaming to eliminate micro-deadzones.
- `PositionThresholdMax`: Movements faster than this mark `stable = false` and **drop the frame**. Set to `100.0`.
- `OrientationThresholdMax`: When rotating a thumb around a virtual joystick, angle deltas change rapidly. Must be `180` to prevent frame drops on 360° circular motions.
- `SizeMax` (`8.0`) and `AspectMax` (`10.0`): Prevents flat-thumb joystick contact shapes from being classified as palms or invalid contacts.

### 4. Capacitive Baseline Noise Subtraction
- `Neutral = mode`: IPTsD computes the statistical mode of the heatmap (the background untouched glass) and subtracts it every 16 frames.
- **CRITICAL**: Never set `Neutral = constant` with `0`. The background electrical noise will flood the detector and result in **0 touch contacts**.
