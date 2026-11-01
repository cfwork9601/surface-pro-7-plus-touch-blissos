# Target Machine & System Profile

## Hardware Specifications
- **Device Model:** Microsoft Surface Pro 7+ (Commercial / Consumer Model 1960 / 1961)
- **Chassis/Board:** Surface Pro 7+ (`124I:00058T:000M:0000000D:0B:15F:1C:01P:16Y:0L:0U:02`)
- **BIOS Version:** `31.101.143`
- **Processor:** 11th Gen Intel(R) Core(TM) i3-1115G4 @ 3.00GHz
  - Architecture: Tiger Lake-U (10nm SuperFin)
  - Cores / Threads: 2 Cores / 4 Threads
  - Base Frequency: 3.00 GHz, Boost: 4.10 GHz
  - Cache: 6 MB Intel Smart Cache
  - TDP: 15W – 28W (Configurable)
- **Graphics:** Intel UHD Graphics for 11th Gen Intel Processors (G4, 48 EUs, up to 1.25 GHz, Iris Xe architecture)
- **Memory (RAM):** 8 GB LPDDR4x-4266 (7,967,564 kB reported)
- **Touch Controller:** Intel Touch Host Controller (ITHC / IPTS)
  - PCI Location: `00:10.6`
  - USB / HID Vendor & Product: `045E:0C1A`
  - Linux Kernel Module: `ithc`
  - HID Node: `/dev/hidraw1`
- **Display:** 12.3-inch PixelSense Display
  - Resolution: 2736 x 1824 (3:2 aspect ratio, 267 PPI)
  - Refresh Rate: 60 Hz
- **Wireless & Connectivity:**
  - Wi-Fi: Intel Wi-Fi 6 AX201 (802.11ax, 160MHz channels)
  - Bluetooth: Intel Bluetooth 5.1 (Integrated with AX201)
- **Buttons / SAM (Surface Aggregator Module):**
  - Driver: `soc_button_array` on ACPI device `MSHW0040:00`
  - Event Handlers: `gpio-keys` (`/dev/input/event11`, `/dev/input/event12`)

---

## Operating System Profile
- **Distribution:** Bliss OS 16.9.7 (Surface Edition, Codename: Typhoon)
- **Android Version:** Android 13 (API Level 33, TQ3A.230901.001.C1)
- **Build ID:** `Bliss-Surface-v16.9.7-x86_64-OFFICIAL-gapps-20241012`
- **Build Fingerprint:** `Android-x86/bliss_x86_64/x86_64:13/TQ3A.230901.001.C1/156:userdebug/test-keys`
- **Kernel:** Linux `6.1.112-gloria-surface-xanmod1` (XanMod preemptive patches + Linux-Surface hardware driver trees)
- **ARM Translation Layer:** `libndk` / Houdini multi-ABI support (`x86_64, arm64-v8a, x86, armeabi-v7a`)
