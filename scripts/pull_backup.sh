#!/bin/bash
set -e

# ==============================================================================
# pull_backup.sh - Pull current live configurations from tablet for safety
# ==============================================================================

TARGET="${1:-192.168.1.107:5555}"
BACKUP_DIR="backups/$(date +%Y%m%d_%H%M%S)"

mkdir -p "$BACKUP_DIR/idc"

echo "==> Pulling live configs from $TARGET to $BACKUP_DIR..."

adb -s "$TARGET" pull /data/vendor/iptsd.conf "$BACKUP_DIR/data_iptsd.conf" 2>/dev/null || true
adb -s "$TARGET" pull /vendor/etc/iptsd.conf "$BACKUP_DIR/vendor_iptsd.conf" 2>/dev/null || true
adb -s "$TARGET" pull /system/vendor/bin/iptsd_runner "$BACKUP_DIR/iptsd_runner" 2>/dev/null || true
adb -s "$TARGET" pull /system/usr/idc/Vendor_045e_Product_0c1a.idc "$BACKUP_DIR/idc/" 2>/dev/null || true
adb -s "$TARGET" pull /system/usr/idc/IPTSD_Virtual_Touchscreen_045E_0C1A.idc "$BACKUP_DIR/idc/" 2>/dev/null || true

echo "Backup completed successfully to: $BACKUP_DIR"
