# Camera Status — Surface Pro 7+ on Bliss OS 16.9.7

**Status: built-in cameras NOT WORKING (unsupported by current kernel).** Checked 2026-11-01.
**Workaround: USB webcam or Android 14+ phone in USB webcam mode works.** See [Workarounds](#workarounds-checked-2026-11-02).

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

## Workarounds (checked 2026-11-02)

The built-in cameras can't work on kernel 6.1. **External USB cameras do work**: the USB webcam (UVC) path is ready on this build.

**Checked on the tablet:**
- `uvcvideo.ko` exists for `6.1.112-gloria-surface-xanmod1` and loads cleanly (pulls in `videobuf2-*`). It is not loaded at boot; it should autoload when a UVC device is plugged in, or load it manually with `adb shell modprobe uvcvideo`.
- `android.hardware.camera.provider@2.5-external-service` (external camera HAL) is running; `/vendor/etc/external_camera_config.xml` has no ignored nodes.
- The `android.hardware.camera.external` feature is declared.

| Option | Needs | Notes |
|---|---|---|
| **1. USB webcam** (recommended) | Any UVC (driver-less) webcam, e.g. Logitech C270/C920 | Plug into the USB-A port (or USB-C via adapter). 720p/1080p models work well with the 3 MB `MaxJpegBufferSize`. |
| **2. Android phone as webcam** | Phone with **Android 14+** and a USB cable | On the phone, set USB mode to **"Webcam"**. The phone then acts as a standard UVC camera, using the same path as option 1. Supported on Pixels and many Android 14+ phones. |
| 3. Built-in cameras | Future Bliss build with Linux >= 6.10, IPU6 support and a libcamera-based camera HAL | Not fixable with config on the current kernel. |

**App compatibility:** external cameras report `LENS_FACING_EXTERNAL`, not front or back. Video-call apps, browsers (WebRTC) and **Open Camera** use them. Some camera apps, such as Google Camera, only list front and back cameras and won't show it.

**Verify after plugging in a camera:**
```bash
adb shell 'lsmod | grep uvcvideo; ls /dev/video*'
adb shell 'dumpsys media.camera | grep -E "Number of camera devices|Facing"'
adb shell 'dmesg | grep -i uvc | tail'
```
If `/dev/video*` exists but the camera count stays 0, restart the HAL: `adb shell 'stop vendor.camera-provider-2-5-ext; start vendor.camera-provider-2-5-ext'`.

## Re-check commands
```bash
adb shell 'ls /dev/video* /dev/media*'
adb shell 'dumpsys media.camera | grep "Number of camera devices"'
adb shell 'zcat /proc/config.gz | grep -i IPU'
```
