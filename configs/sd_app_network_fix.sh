#!/system/bin/sh
# Restore network access for apps installed on the adopted SD card.
#
# Problem: Bliss (Lineage-based) enables "restricted networking mode"; only
# allowlisted uids (RESTRICTED_MATCH in netd's BPF uid owner map) can use the
# network. NetworkPolicyManager builds that allowlist at boot, before the
# adopted SD card is mounted, so apps on the card are skipped and never re-added
# -> "no internet" in those apps while internal apps work.
#
# Fix: after boot, once the SD volume and its packages are available, check
# whether any SD app is missing from the allowlist and, only then, toggle
# restricted_networking_mode 1 -> 0 -> 1 so the allowlist is rebuilt.
# Started by /system/etc/init/sd_app_network_fix.rc on sys.boot_completed=1.

PATH=/system/bin:/system/xbin
TAG=sd_app_network_fix

# Respect the user's choice: do nothing if restricted mode is off.
[ "$(settings get global restricted_networking_mode)" = "1" ] || {
    log -t $TAG "restricted_networking_mode off, nothing to do"; exit 0; }

# Wait (max ~3 min) for the adopted volume and its apps.
i=0
while [ $i -lt 90 ]; do
    if sm list-volumes private 2>/dev/null | grep -qE "^private:[0-9,]+ mounted" \
       && pm list packages -f -3 2>/dev/null | grep -q "/mnt/expand/"; then
        break
    fi
    i=$((i + 1)); sleep 2
done
[ $i -ge 90 ] && { log -t $TAG "no adopted-storage apps found, exiting"; exit 0; }
sleep 5   # let NetworkPolicyManager settle

# Find SD apps missing from the restricted-mode allowlist.
owner_map=$(dumpsys connectivity trafficcontroller 2>/dev/null)
missing=""
for line in $(pm list packages -f -3 -U 2>/dev/null | grep "/mnt/expand/" | tr ' ' '|'); do
    uid=${line##*uid:}
    pkg=${line%%"|"*}; pkg=${pkg##*=}   # quote "|": mksh treats a bare | in patterns as alternation
    echo "$owner_map" | grep -qE "^ *$uid .*RESTRICTED_MATCH" || missing="$missing $pkg"
done

if [ -z "$missing" ]; then
    log -t $TAG "all adopted-storage apps already allowlisted"
    exit 0
fi

log -t $TAG "not allowlisted:$missing -> rebuilding restricted-mode allowlist"
settings put global restricted_networking_mode 0
sleep 1
settings put global restricted_networking_mode 1
log -t $TAG "done"
