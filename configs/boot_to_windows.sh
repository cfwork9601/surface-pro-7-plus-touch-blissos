#!/system/bin/sh
# Boot into Windows once: point the UEFI BootNext variable at the
# "Windows Boot Manager" firmware entry, then reboot. The next boot after that
# follows BootOrder again (BlissOS first). Installed to /system/etc by install.sh,
# run as root by the Boot Switch app (gesture-app sibling: bootswitch-app/).
#   --no-reboot   set BootNext only (for testing)
#   --clear       remove a pending BootNext
G=8be4df61-93ca-11d2-aa0d-00e098032b8c
V=/sys/firmware/efi/efivars

grep -q " $V efivarfs " /proc/mounts || mount -t efivarfs efivarfs "$V" || {
    echo "cannot mount efivarfs" >&2; exit 2; }

if [ "$1" = "--clear" ]; then
    [ -e "$V/BootNext-$G" ] && { chattr -i "$V/BootNext-$G" 2>/dev/null; rm "$V/BootNext-$G"; }
    exit 0
fi

entry=
for f in "$V"/Boot[0-9A-F][0-9A-F][0-9A-F][0-9A-F]-$G; do
    [ -e "$f" ] || continue
    if tr -d '\000' < "$f" | grep -q 'Windows Boot Manager'; then
        n=${f##*/Boot}; entry=${n%%-*}; break
    fi
done
[ -n "$entry" ] || { echo "Windows Boot Manager entry not found" >&2; exit 3; }

# Value = 4-byte attributes (NV|BS|RT = 7) + entry number as UINT16 little-endian.
lo=$(printf '%03o' $((0x$entry & 0xff)))
hi=$(printf '%03o' $((0x$entry >> 8)))
[ -e "$V/BootNext-$G" ] && chattr -i "$V/BootNext-$G" 2>/dev/null
# efivarfs needs the whole value in one write(), so build it first, then copy.
tmp=/data/local/tmp/.bootnext.$$
printf "\\007\\000\\000\\000\\$lo\\$hi" > "$tmp"
dd if="$tmp" of="$V/BootNext-$G" bs=6 count=1 2>/dev/null; rc=$?
rm -f "$tmp"
[ $rc -eq 0 ] || { echo "cannot write BootNext" >&2; exit 4; }
echo "BootNext=Boot$entry (Windows Boot Manager)"

[ "$1" = "--no-reboot" ] && exit 0
sync
svc power reboot || reboot
