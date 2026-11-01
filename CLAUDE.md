# CLAUDE.md - Surface Pro 7+ Bliss OS Project Guide

Authoritative workspace reference for Claude Code when managing the **Microsoft Surface Pro 7+** running **Bliss OS 16.9.7**.

---

## 1. Environment & Hardware Safety (CRITICAL)

### Host Machine Profile (Where you run commands)
- **Model:** Apple iMac 17,1 (Late 2015 27-inch 5K Retina) running Fedora Linux 43.
- **Dying Internal Blade SSD (`/dev/sdb` / `144d:a801`):** Physically failing with unrecoverable media errors; causes 90+s ATA bus freezes if queried. **NEVER suggest mounting, scanning, querying, or formatting `/dev/sdb`.**
- **GPU Quirks:** AMD Tonga GPU requires `amdgpu.dpm=0`. Never alter graphics power management parameters.

### Target Device Profile (Connected via ADB)
- **Model:** Microsoft Surface Pro 7+ (Model 1960 / 1961, Tiger Lake 11th Gen i3-1115G4, 8GB RAM).
- **OS:** Bliss OS 16.9.7 (Surface Edition, Android 13 TQ3A.230901.001.C1, Kernel `6.1.112-gloria-surface-xanmod1`).
- **Touch Hardware:** Intel Touch Host Controller (ITHC / IPTS `045E:0C1A`).
- **Connection:** Default ADB target is `192.168.1.107:5555`. Reconnect with `./scripts/connect.sh`.

---

## 2. Fast Workflow Commands

Always execute commands through the repository scripts or target explicit ADB serial:

```bash
./scripts/connect.sh          # Auto-reconnect Wi-Fi/USB and ensure adb root
./scripts/status.sh           # Run diagnostic check on IPTSD, EventHub, and battery
./scripts/restart_iptsd.sh    # Safely restart touch daemon and sync buffers
./scripts/screencap.sh        # Pull screenshot from tablet to host
./scripts/pull_backup.sh      # Backup current configs from device to backups/
./install.sh                  # Deploy full repository configs to device
```

---

## 3. Architecture & Core Invariants

Do not modify or propose changes that break these verified system invariants:

1. **Dual Device Conflict (`ithc` vs `iptsd`)**:
   - The Linux kernel driver `ithc` exposes a raw input node (`Intel Touch Host Controller`).
   - Android `EventHub` will lock to single-touch pointer if this node exists.
   - `/system/vendor/bin/iptsd_runner` actively removes raw ITHC nodes and runs a background watchdog. Ensure this runner is never bypassed.
2. **Coordinate Orientation**:
   - Surface digitizer coordinates are physically inverted 180°.
   - `InvertX = true` and `InvertY = true` in `/data/vendor/iptsd.conf` must remain set.
3. **Gaming & Virtual Joystick Dragging**:
   - `PositionThresholdMin = 0.0`: Must remain `0.0` (zero deadzone for fine aiming).
   - `PositionThresholdMax = 100.0`: Prevents fast flicks from dropping frames.
   - `OrientationThresholdMin = 0` / `OrientationThresholdMax = 180`: Prevents circular thumb rotation around virtual joysticks from setting `contact.stable = false` (which drops frames).
   - `SizeMax = 8.0` / `AspectMax = 10.0`: Prevents flattened thumbs from being invalidated by `Validator` and triggering premature touch releases (`lift_multitouch`).
4. **Capacitive Baseline Calibration**:
   - **`Neutral = mode` MUST remain active in `iptsd.conf`.**
   - NEVER set `Neutral = constant` or `NeutralValue = 0`. Without mode-based baseline subtraction, the daemon detects electrical floor noise across the entire glass, resulting in **0 touch contacts**.
5. **Disk Commit**:
   - The root filesystem is mounted `rw` on `/dev/loop0`.
   - **Always run `adb shell sync`** after writing files or restarting daemons to ensure persistence across reboots.

---

## 4. Progressive Reference Docs

Consult these detailed references on demand:
- **Input Pipeline & Mathematics:** See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- **Full Hardware Specs (DMI / PCI / ACPI):** See [`docs/HARDWARE_SPECS.md`](docs/HARDWARE_SPECS.md)
- **Troubleshooting & Diagnostic Trees:** See [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md)
- **Complete Command Cheatsheet:** See [`docs/COMMANDS.md`](docs/COMMANDS.md)
