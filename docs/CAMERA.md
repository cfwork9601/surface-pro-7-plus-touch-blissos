# Camera Status — Surface Pro 7+ on Bliss OS 16.9.7

**Status: NOT WORKING (unsupported by current kernel).** Checked 2026-11-01.

## Hardware
| ACPI ID     | Sensor  | Role             |
|-------------|---------|------------------|
| `INT33BE:00`| OV5693  | Front 5 MP       |
| `INT347A:00`| OV8865  | Rear 8 MP        |
| `INT347E:00`| OV7251  | IR (Windows Hello)|
| `INT3472:00-02` | —   | Camera PMIC / GPIO power glue |

Image processor: **Intel IPU6** (Tiger Lake), PCI `0000:00:05.0` `8086:9a19`.

## Findings
- No `/dev/video*`, `/dev/media*`, or `/dev/v4l-subdev*` nodes exist.
- PCI `8086:9a19` has **no driver bound**.
- Kernel `6.1.112-gloria-surface-xanmod1` only ships **IPU3** (`ipu3-cio2`, `ipu3-imgu`) for Skylake/Kaby Lake Surfaces. It has **no IPU6 driver** (`CONFIG_VIDEO_INTEL_IPU6` is absent).
- Sensor modules (`ov8865`, `ov7251`, `atomisp_ov5693`, `int3472`) load, but nothing is bound, because there is no IPU to attach them to. The INT3472 devices sit in `waiting_for_supplier`.
- Android: `cameraserver` and `vendor.camera-provider-2-5-ext` (the external USB/UVC HAL) are running, and `dumpsys media.camera` reports **0 camera devices**.

## Why it can't be fixed with config
- Upstream IPU6 input-system support landed in Linux **6.10**, so 6.1 is too old.
- Even with IPU6, there is no ISP in the kernel. Images need processing in userspace (libcamera software ISP, or Intel's proprietary IPU6 HAL). Bliss OS has no Android camera HAL for that pipeline.
- Realistic paths: a future Bliss/kernel build with IPU6 + a libcamera-based Android HAL, or use a **USB UVC webcam** (`CONFIG_USB_VIDEO_CLASS=m` and the external camera HAL are already present).

## Re-check commands
```bash
adb shell 'ls /dev/video* /dev/media*'
adb shell 'dumpsys media.camera | grep "Number of camera devices"'
adb shell 'zcat /proc/config.gz | grep -i IPU'
```
